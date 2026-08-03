#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="$script_dir/../templates/workflows/ci.yml"
workspace="$(mktemp -d)"
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
assert_contains \
  "$website_job" \
  'node website/scripts/build-llms.test.js' \
  'website job 缺少 llms builder 测试'
assert_contains \
  "$website_job" \
  'yarn workspace "${{ steps.website.outputs.name }}" typecheck' \
  'website job 缺少 workspace typecheck'
assert_contains \
  "$website_job" \
  'yarn workspace "${{ steps.website.outputs.name }}" build' \
  'website job 缺少 workspace build'

llms_line="$(grep -nF 'node website/scripts/build-llms.test.js' "$website_job" | cut -d: -f1)"
typecheck_line="$(grep -nF 'yarn workspace "${{ steps.website.outputs.name }}" typecheck' "$website_job" | cut -d: -f1)"
build_line="$(grep -nF 'yarn workspace "${{ steps.website.outputs.name }}" build' "$website_job" | cut -d: -f1)"

if ((llms_line >= typecheck_line || typecheck_line >= build_line)); then
  fail 'website job 必须依次运行 llms 测试、typecheck、build'
fi

printf 'PASS: shared CI website contract\n'
