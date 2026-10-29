import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("setup_repo", ROOT / "scripts/setup_repo.py")
setup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(setup)
BASE = "repos/unif-design/contract-fixture"
TEMPLATE = json.loads((ROOT / "scripts/rulesets/protect-main.json").read_text())
SETTINGS = json.loads((ROOT / "templates/repository-settings.json").read_text())
CHECKS = ["actionlint", "lint", "test", "build-library", "build-android", "build-ios", "verified"]


class GithubFixture:
    def __init__(self):
        self.repo = copy.deepcopy(SETTINGS)
        self.repo.update(default_branch="main", permissions={"admin": True}, homepage=None)
        self.repo["security_and_analysis"]["dependabot_security_updates"] = {"status": "disabled"}
        self.ruleset = {**copy.deepcopy(TEMPLATE), "id": 1}
        self.reporting = True
        self.codeql = "not-configured"
        self.checks = list(CHECKS)
        self.native = False
        self.native_checks = []
        self.website = False
        self.site = None
        self.ignore_writes = False
        self.calls = []

    @property
    def writes(self):
        return [call for call in self.calls if call[1] != "GET"]

    def api(self, endpoint, method="GET", body=None, missing_ok=False):
        self.calls.append((endpoint, method, copy.deepcopy(body)))
        if method != "GET":
            if self.ignore_writes:
                return None
            if endpoint == BASE:
                for key, value in body.items():
                    if isinstance(value, dict):
                        self.repo[key].update(copy.deepcopy(value))
                    else:
                        self.repo[key] = value
            elif "/rulesets" in endpoint:
                self.ruleset = {**copy.deepcopy(body), "id": 1}
            elif endpoint.endswith("/private-vulnerability-reporting"):
                self.reporting = True
            elif endpoint.endswith("/automated-security-fixes"):
                self.repo["security_and_analysis"]["dependabot_security_updates"]["status"] = "disabled"
            elif endpoint.endswith("/code-scanning/default-setup"):
                self.codeql = body["state"]
            elif endpoint.endswith("/pages"):
                self.site = {"html_url": "https://unif-design.github.io/contract-fixture/", **body}
            else:
                raise AssertionError((endpoint, method, body))
            return None
        if endpoint == BASE:
            return copy.deepcopy(self.repo)
        if "/contents/.github/workflows/" in endpoint:
            if endpoint.endswith("deploy-docs.yml") and self.website:
                return {"type": "file"}
            if endpoint.endswith("native-lint.yml") and self.native:
                return {"type": "file"}
            assert missing_ok
            return None
        if "/actions/workflows/ci.yml/runs?" in endpoint:
            return {"workflow_runs": [{"id": 10}]}
        if "/actions/workflows/native-lint.yml/runs?" in endpoint:
            return {"workflow_runs": [{"id": 20}]}
        if "/actions/runs/10/jobs?" in endpoint:
            offset = 100 if endpoint.endswith("page=2") else 0
            return {"jobs": [{"name": name} for name in self.checks[offset:offset + 100]]}
        if "/actions/runs/20/jobs?" in endpoint:
            return {"jobs": [{"name": name} for name in self.native_checks]}
        if endpoint.startswith(BASE + "/rulesets?"):
            return [] if self.ruleset is None else [{"id": 1, "name": "protect main"}]
        if endpoint == BASE + "/rulesets/1":
            return copy.deepcopy(self.ruleset)
        if endpoint.endswith("/private-vulnerability-reporting"):
            return {"enabled": self.reporting}
        if endpoint.endswith("/code-scanning/default-setup"):
            return {"state": self.codeql}
        if endpoint.endswith("/pages"):
            assert missing_ok or self.site is not None
            return copy.deepcopy(self.site)
        raise AssertionError(endpoint)


class SetupTests(unittest.TestCase):
    def run_setup(self, fixture, *args):
        with patch.object(setup, "api", fixture.api), patch.object(sys, "argv", ["setup-repo", "contract-fixture", *args]), contextlib.redirect_stdout(io.StringIO()):
            return setup.main()

    def test_matching_configuration_never_writes(self):
        fixture = GithubFixture()
        fixture.ruleset["rules"][2]["parameters"]["server_default"] = False
        self.assertEqual(self.run_setup(fixture), 0)
        self.assertEqual(fixture.writes, [])

    def test_check_reports_missing_configuration_without_writing(self):
        fixture = GithubFixture()
        fixture.ruleset = None
        fixture.repo["allow_merge_commit"] = True
        self.assertEqual(self.run_setup(fixture, "--check"), 1)
        self.assertEqual(fixture.writes, [])

    def test_only_missing_settings_are_applied_and_read_back(self):
        fixture = GithubFixture()
        fixture.ruleset = None
        fixture.reporting = False
        fixture.repo["allow_merge_commit"] = True
        self.assertEqual(self.run_setup(fixture), 0)
        self.assertEqual([call[1] for call in fixture.writes], ["PATCH", "POST", "PUT"])
        self.assertEqual(fixture.writes[0][2], {"allow_merge_commit": False})
        self.assertEqual(fixture.writes[1][2]["bypass_actors"], TEMPLATE["bypass_actors"])
        fixture.calls.clear()
        self.assertEqual(self.run_setup(fixture), 0)
        self.assertEqual(fixture.writes, [])

    def test_missing_ci_check_prevents_every_write(self):
        fixture = GithubFixture()
        fixture.checks.remove("verified")
        fixture.repo["allow_merge_commit"] = True
        with self.assertRaisesRegex(RuntimeError, "verified"):
            self.run_setup(fixture)
        self.assertEqual(fixture.writes, [])

    def test_ci_jobs_are_paginated(self):
        fixture = GithubFixture()
        fixture.checks = [f"matrix-{index}" for index in range(100)] + CHECKS
        self.assertEqual(self.run_setup(fixture, "--check"), 0)

    def test_native_repository_requires_both_native_checks_before_writing(self):
        fixture = GithubFixture()
        fixture.native = True
        with self.assertRaisesRegex(RuntimeError, "lint-cpp, lint-kotlin"):
            self.run_setup(fixture)
        self.assertEqual(fixture.writes, [])
        fixture.native_checks = ["lint-cpp", "lint-kotlin"]
        self.assertEqual(self.run_setup(fixture), 0)
        checks = fixture.ruleset["rules"][3]["parameters"]["required_status_checks"]
        self.assertEqual({check["context"] for check in checks}, set(CHECKS + fixture.native_checks))
        self.assertEqual([call[1] for call in fixture.writes], ["PUT"])

    def test_unknown_security_state_is_not_assumed_disabled(self):
        fixture = GithubFixture()
        fixture.repo["allow_merge_commit"] = True
        del fixture.repo["security_and_analysis"]["dependabot_security_updates"]
        with self.assertRaisesRegex(RuntimeError, "未取得自动安全更新状态"):
            self.run_setup(fixture)
        self.assertEqual(fixture.writes, [])

    def test_disable_automatic_security_prs_only_when_enabled(self):
        fixture = GithubFixture()
        fixture.repo["security_and_analysis"]["dependabot_security_updates"]["status"] = "enabled"
        self.assertEqual(self.run_setup(fixture), 0)
        self.assertEqual(fixture.writes, [(BASE + "/automated-security-fixes", "DELETE", None)])

    def test_add_required_check_without_dropping_existing_checks(self):
        fixture = GithubFixture()
        checks = fixture.ruleset["rules"][3]["parameters"]["required_status_checks"]
        checks[:] = [check for check in checks if check["context"] != "verified"]
        checks[0]["integration_id"] = 456
        checks.append({"context": "custom-check", "integration_id": 123})
        fixture.ruleset["rules"].append({"type": "required_signatures"})
        self.assertEqual(self.run_setup(fixture), 0)
        result = fixture.ruleset["rules"][3]["parameters"]["required_status_checks"]
        self.assertIn({"context": "custom-check", "integration_id": 123}, result)
        self.assertIn({"context": "actionlint", "integration_id": 456}, result)
        self.assertIn({"context": "verified"}, result)
        self.assertIn({"type": "required_signatures"}, fixture.ruleset["rules"])

    def test_failed_read_back_does_not_report_success(self):
        fixture = GithubFixture()
        fixture.ruleset = None
        fixture.ignore_writes = True
        with self.assertRaisesRegex(RuntimeError, "回读仍有差异"):
            self.run_setup(fixture)

    def test_pages_are_created_only_with_the_deployment_workflow(self):
        fixture = GithubFixture()
        self.assertEqual(self.run_setup(fixture), 0)
        self.assertFalse(any(call[0].endswith("/pages") for call in fixture.calls))
        fixture.website = True
        self.assertEqual(self.run_setup(fixture), 0)
        self.assertEqual(fixture.repo["homepage"], fixture.site["html_url"])
        fixture.calls.clear()
        self.assertEqual(self.run_setup(fixture), 0)
        self.assertEqual(fixture.writes, [])

    def test_non_admin_stops_before_mutations(self):
        fixture = GithubFixture()
        fixture.repo["permissions"]["admin"] = False
        with self.assertRaisesRegex(RuntimeError, "管理员权限"):
            self.run_setup(fixture)
        self.assertEqual(fixture.writes, [])

    def test_api_forbidden_is_not_treated_as_missing(self):
        result = type("Result", (), {"returncode": 1, "stderr": "gh: Forbidden (HTTP 403)", "stdout": ""})()
        with patch.object(setup.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(RuntimeError, "HTTP 403"):
                setup.api("repos/unif-design/fixture/contents/file", missing_ok=True)
        result.stderr = "gh: Not Found (HTTP 404)"
        with patch.object(setup.subprocess, "run", return_value=result):
            self.assertIsNone(setup.api("repos/unif-design/fixture/contents/file", missing_ok=True))


if __name__ == "__main__":
    unittest.main()
