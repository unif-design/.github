#!/usr/bin/env python3
"""按组织模板核对、补齐单个仓库设置；不配置组织共用凭据。"""

import argparse
import copy
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote


ROOT = Path(__file__).resolve().parent.parent


def api(endpoint, method="GET", body=None, missing_ok=False):
    command = ["gh", "api", "--method", method, endpoint]
    if body is not None:
        command.extend(["--input", "-"])
    result = subprocess.run(
        command, input=json.dumps(body) if body is not None else None,
        text=True, capture_output=True, check=False,
    )
    if result.returncode:
        if missing_ok and "(HTTP 404)" in result.stderr:
            return None
        raise RuntimeError(f"{method} {endpoint}: {result.stderr.strip()}")
    return json.loads(result.stdout) if result.stdout.strip() else None


def pages(endpoint, key=None):
    page = 1
    while True:
        separator = "&" if "?" in endpoint else "?"
        result = api(f"{endpoint}{separator}per_page=100&page={page}")
        items = result[key] if key else result
        yield from items
        if len(items) < 100:
            return
        page += 1


def differences(current, expected):
    result = {}
    for key, value in expected.items():
        actual = current.get(key)
        if isinstance(value, dict):
            nested = differences(actual if isinstance(actual, dict) else {}, value)
            if nested:
                result[key] = nested
        elif actual != value:
            result[key] = value
    return result


def matches(current, expected):
    if isinstance(expected, dict):
        return isinstance(current, dict) and all(
            key in current and matches(current[key], value)
            for key, value in expected.items()
        )
    if isinstance(expected, list):
        return isinstance(current, list) and len(current) == len(expected) and all(
            any(matches(item, wanted) for item in current) for wanted in expected
        )
    return current == expected


def desired_rules(template, current):
    desired = copy.deepcopy(template)
    if current is None:
        return desired
    rules = {rule["type"]: copy.deepcopy(rule) for rule in current["rules"]}
    for rule in template["rules"]:
        kind = rule["type"]
        existing = rules.get(kind, {})
        parameters = {**existing.get("parameters", {}), **rule.get("parameters", {})}
        if kind == "required_status_checks":
            checks = {
                check["context"]: check
                for check in existing.get("parameters", {}).get("required_status_checks", [])
            }
            for check in rule["parameters"]["required_status_checks"]:
                checks[check["context"]] = {**checks.get(check["context"], {}), **check}
            parameters["required_status_checks"] = list(checks.values())
        rules[kind] = {"type": kind, **({"parameters": parameters} if parameters else {})}
    desired["rules"] = list(rules.values())
    return desired


def assert_registered_checks(base, branch, required, native):
    registered = set()
    workflows = ["ci.yml"] + (["native-lint.yml"] if native else [])
    for workflow in workflows:
        runs = api(f"{base}/actions/workflows/{workflow}/runs?branch={quote(branch, safe='')}&per_page=5")
        for run in runs["workflow_runs"]:
            registered.update(job["name"] for job in pages(f"{base}/actions/runs/{run['id']}/jobs", "jobs"))
            if required <= registered:
                return
    raise RuntimeError("CI 尚未注册全部必需检查，未修改远端：" + ", ".join(sorted(required - registered)))


def plan(repository):
    base = f"repos/unif-design/{repository}"
    repo = api(base)
    if not repo.get("permissions", {}).get("admin"):
        raise RuntimeError("需要该仓库的管理员权限才能完整核对和配置远端设置。")
    native = api(f"{base}/contents/.github/workflows/native-lint.yml", missing_ok=True) is not None
    template_name = "protect-main-native.json" if native else "protect-main.json"
    template = json.loads((ROOT / "scripts/rulesets" / template_name).read_text())
    required = {
        check["context"] for rule in template["rules"]
        if rule["type"] == "required_status_checks"
        for check in rule["parameters"]["required_status_checks"]
    }
    assert_registered_checks(base, repo["default_branch"], required, native)

    changes = []
    desired = json.loads((ROOT / "templates/repository-settings.json").read_text())
    patch = differences(repo, desired)
    if patch:
        changes.append(("仓库合并选项／安全开关", "PATCH", base, patch))

    owned = [rule for rule in pages(f"{base}/rulesets?includes_parents=false") if rule["name"] == template["name"]]
    if len(owned) > 1:
        raise RuntimeError("存在多个同名 protect main 规则，请先明确保留对象。")
    current = api(f"{base}/rulesets/{owned[0]['id']}") if owned else None
    rules = desired_rules(template, current)
    if current is None:
        changes.append(("主分支保护", "POST", f"{base}/rulesets", rules))
    elif not matches(current, rules):
        changes.append(("主分支保护", "PUT", f"{base}/rulesets/{current['id']}", rules))

    reporting = api(f"{base}/private-vulnerability-reporting")
    if reporting.get("enabled") is not True:
        changes.append(("私密漏洞报告", "PUT", f"{base}/private-vulnerability-reporting", None))
    security_updates = repo.get("security_and_analysis", {}).get("dependabot_security_updates", {}).get("status")
    if security_updates not in ("enabled", "disabled"):
        raise RuntimeError("未取得自动安全更新状态，不能将缺失信息视为已关闭。")
    if security_updates == "enabled":
        changes.append(("关闭自动安全更新 PR", "DELETE", f"{base}/automated-security-fixes", None))
    codeql = api(f"{base}/code-scanning/default-setup")
    if codeql["state"] != "not-configured":
        changes.append(("CodeQL 默认设置", "PATCH", f"{base}/code-scanning/default-setup", {"state": "not-configured"}))

    website = api(f"{base}/contents/.github/workflows/deploy-docs.yml", missing_ok=True)
    if website is not None:
        site = api(f"{base}/pages", missing_ok=True)
        if site is None:
            changes.append(("Pages 与网站入口", "POST", f"{base}/pages", {"build_type": "workflow"}))
        else:
            if site["build_type"] != "workflow":
                changes.append(("Pages 构建方式", "PUT", f"{base}/pages", {"build_type": "workflow"}))
            if repo.get("homepage") != site["html_url"]:
                changes.append(("网站入口", "PATCH", base, {"homepage": site["html_url"]}))
    return changes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", help="unif-design 下的仓库名")
    parser.add_argument("--check", action="store_true", help="只读核验；有差异或前置缺失时返回非零")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.repository):
        parser.error("只接受仓库名，不接受组织名、URL 或路径。")
    changes = plan(args.repository)
    if args.check:
        for label, _, _, _ in changes:
            print(f"需补齐：{label}")
        if changes:
            return 1
    else:
        for label, method, endpoint, body in changes:
            print(f"配置：{label}", flush=True)
            api(endpoint, method, body)
            if method == "POST" and endpoint.endswith("/pages"):
                site = api(endpoint)
                api(f"repos/unif-design/{args.repository}", "PATCH", {"homepage": site["html_url"]})
        remaining = plan(args.repository) if changes else []
        if remaining:
            raise RuntimeError("配置后回读仍有差异：" + ", ".join(item[0] for item in remaining))
    print(f"通过：unif-design/{args.repository} 远端仓库设置与主分支规则符合模板。")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, KeyError, TypeError) as error:
        print(f"失败：{error}", file=sys.stderr)
        sys.exit(1)
