#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup_script="$script_dir/setup-repo.sh"
workspace="$(mktemp -d)"
fake_bin="$workspace/bin"
gh_log="$workspace/gh-calls.log"

cleanup() {
  rm -rf "$workspace"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

trap cleanup EXIT

mkdir -p "$fake_bin"
cat >"$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$GH_CALL_LOG"

if [[ "${1:-}" == 'api' && "${2:-}" == 'repos/unif-design/contract-fixture/contents/.github/workflows/native-lint.yml' ]]; then
  exit 1
fi
if [[ "${1:-}" == 'api' && "${2:-}" == 'repos/unif-design/contract-fixture/contents/.github/workflows/deploy-docs.yml' ]]; then
  exit 1
fi
if [[ "${1:-}" == 'api' && "${2:-}" == 'repos/unif-design/contract-fixture/pages' ]]; then
  exit 1
fi

exit 0
EOF
chmod +x "$fake_bin/gh"

if ! PATH="$fake_bin:$PATH" GH_CALL_LOG="$gh_log" bash "$setup_script" contract-fixture >/dev/null; then
  fail 'setup-repo.sh 在受控 gh 环境下退出非零'
fi

grep -Fxq \
  'api -X DELETE repos/unif-design/contract-fixture/automated-security-fixes' \
  "$gh_log" || fail 'setup-repo.sh 未显式关闭 Dependabot security updates'

printf 'PASS: setup-repo security settings contract\n'
