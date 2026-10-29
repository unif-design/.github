#!/usr/bin/env bash
# 按组织模板配置单个仓库；已有设置跳过，--check 只读核验。
# 先同步并运行 CI，确保模板要求的检查已经注册。
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$script_dir/setup_repo.py" "$@"
