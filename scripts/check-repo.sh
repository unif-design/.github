#!/usr/bin/env bash
# 在组织标准源中只读核验目标仓；--release 追加公开交付前置。
set -euo pipefail
mode=source
if [[ "${1:-}" == --release ]]; then mode=release; shift; fi
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "用法: $0 [--release] <repo-name> [target-path]" >&2
  exit 2
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$1"
target="${2:-$(cd "$script_dir/../.." && pwd)/$repo}"
bash "$script_dir/sync-repo.sh" --check "$repo" "$target"
node "$script_dir/../templates/scripts/check-library.cjs" "$mode" "$target"
