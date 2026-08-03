#!/usr/bin/env bash

# GitHub Actions 表达式在本文件里是待断言的字面量,不能让 shell 展开。
# shellcheck disable=SC2016

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="$script_dir/../templates/workflows/ci.yml"
validation_workflow="$script_dir/../.github/workflows/validate.yml"
workspace="$(mktemp -d)"
changes_job="$workspace/changes-job.yml"
website_filter="$workspace/website-filter.yml"
website_job="$workspace/website-job.yml"

cleanup() {
  rm -rf "$workspace"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  local label="$3"

  grep -Fq -- "$expected" "$file" || fail "$label"
}

trap cleanup EXIT

[[ -f "$template" ]] || fail "CI 模板不存在:$template"

awk '
  $0 == "  changes:" {
    in_job = 1
  }
  in_job && $0 != "  changes:" && $0 ~ /^  [a-z][a-z0-9_-]*:$/ {
    exit
  }
  in_job {
    print
  }
' "$template" >"$changes_job"

[[ -s "$changes_job" ]] || fail 'CI 模板缺少 changes job'
assert_contains \
  "$changes_job" \
  'contents: read' \
  'changes job 缺少 checkout 所需 contents: read'
assert_contains \
  "$changes_job" \
  'pull-requests: read' \
  'changes job 缺少 paths-filter 所需 pull-requests: read'

assert_contains \
  "$template" \
  'website: ${{ steps.filter.outputs.website }}' \
  'changes job 缺少 website output'

awk '
  $0 == "            website:" {
    in_filter = 1
    next
  }
  in_filter && $0 ~ /^            [a-z][a-z0-9_-]*:$/ {
    exit
  }
  in_filter {
    print
  }
' "$template" >"$website_filter"

[[ -s "$website_filter" ]] || fail 'changes filters 缺少 website filter'

for required_path in \
  "AGENTS.md" \
  "website/**" \
  "src/**" \
  "package.json" \
  "yarn.lock" \
  "tsconfig*.json" \
  ".nvmrc" \
  ".github/actions/**" \
  ".github/workflows/ci.yml"; do
  assert_contains \
    "$website_filter" \
    "- '$required_path'" \
    "website filter 缺少 $required_path"
done

awk '
  $0 == "  website:" {
    in_job = 1
  }
  in_job && $0 != "  website:" && $0 ~ /^  [a-z][a-z0-9_-]*:$/ {
    exit
  }
  in_job {
    print
  }
' "$template" >"$website_job"

[[ -s "$website_job" ]] || fail 'CI 模板缺少 website job'

assert_contains "$website_job" 'needs: changes' 'website job 未依赖 changes'
assert_contains \
  "$website_job" \
  "if: needs.changes.outputs.website == 'true'" \
  'website job 未使用 website output 作为运行条件'
assert_contains \
  "$website_job" \
  'uses: ./.github/actions/setup' \
  'website job 未复用共享 setup action'
assert_contains \
  "$website_job" \
  "node -p \"require('./website/package.json').name\"" \
  'website job 未动态读取 website workspace 名'
assert_contains "$website_job" 'id: website' 'website resolver 缺少稳定 step id'
assert_contains \
  "$website_job" \
  'printf '\''name=%s\n'\'' "$WEBSITE_WORKSPACE" >> "$GITHUB_OUTPUT"' \
  'website resolver 未写入 GITHUB_OUTPUT'
assert_contains \
  "$website_job" \
  'node website/scripts/build-llms.test.js' \
  'website job 缺少 llms builder 测试'
assert_contains \
  "$website_job" \
  'WEBSITE_WORKSPACE: ${{ steps.website.outputs.name }}' \
  'website 命令未通过 env 接收 workspace 名'
website_env_count="$(
  grep -Fc 'WEBSITE_WORKSPACE: ${{ steps.website.outputs.name }}' "$website_job"
)"
[[ "$website_env_count" -eq 2 ]] ||
  fail "website typecheck / build 必须分别注入 workspace env,实际为 $website_env_count"
assert_contains \
  "$website_job" \
  'yarn workspace "$WEBSITE_WORKSPACE" typecheck' \
  'website job 缺少 workspace typecheck'
assert_contains \
  "$website_job" \
  'yarn workspace "$WEBSITE_WORKSPACE" build' \
  'website job 缺少 workspace build'

llms_line="$(grep -nF 'node website/scripts/build-llms.test.js' "$website_job" | cut -d: -f1)"
typecheck_line="$(grep -nF 'yarn workspace "$WEBSITE_WORKSPACE" typecheck' "$website_job" | cut -d: -f1)"
build_line="$(grep -nF 'yarn workspace "$WEBSITE_WORKSPACE" build' "$website_job" | cut -d: -f1)"

if ((llms_line >= typecheck_line || typecheck_line >= build_line)); then
  fail 'website job 必须依次运行 llms 测试、typecheck、build'
fi

if grep -Fq 'run: yarn workspace "${{ steps.website.outputs.name }}"' "$website_job"; then
  fail 'website workspace output 不得直接插值进 run shell'
fi

node "$script_dir/ci-filter-contract.test.mjs"

[[ -f "$validation_workflow" ]] ||
  fail '共享仓缺少自动执行模板契约的 validate workflow'
for validation_contract in \
  'pull_request:' \
  'push:' \
  'shellcheck scripts/*.sh' \
  'bash -n scripts/*.sh' \
  'bash scripts/ci-template.test.sh' \
  'bash scripts/sync-agent-standards.test.sh' \
  './actionlint' \
  'templates/workflows/ci.yml'; do
  assert_contains \
    "$validation_workflow" \
    "$validation_contract" \
    "validate workflow 缺少契约:$validation_contract"
done

printf 'PASS: shared CI website contract\n'
