#!/usr/bin/env bash

set -euo pipefail

begin_marker='<!-- BEGIN UNIF REACT NATIVE STANDARD -->'
end_marker='<!-- END UNIF REACT NATIVE STANDARD -->'
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="$script_dir/../templates/AGENTS.md"

usage() {
  printf 'Usage: %s [--check] <repo-name> [target-path]\n' "${0##*/}" >&2
  exit 2
}

file_mode() {
  local mode
  if mode="$(stat -f '%Lp' "$1" 2>/dev/null)"; then
    printf '%s\n' "$mode"
  elif mode="$(stat -c '%a' "$1" 2>/dev/null)"; then
    printf '%s\n' "$mode"
  else
    return 1
  fi
}

check_only=false
if [[ "${1:-}" == --check ]]; then check_only=true; shift; fi
[[ $# -ge 1 && $# -le 2 ]] || usage

repo_name="$1"
target_dir="${2:-$PWD}"

[[ "$repo_name" =~ ^react-native-[a-z0-9-]+$ ]] || usage
package="@unif/$repo_name"
case "$repo_name" in
  react-native-camera|react-native-design|react-native-hms-scan|react-native-umeng|react-native-chat|react-native-icons)
    library_skill="unif-${repo_name#react-native-}"
    library_skill_entry='本库能力的使用、维护和排障使用 `unif-portal-dev-skills:'"$library_skill"'`，只读取当前任务相关资料。'
    ;;
  *) library_skill_entry='本库能力的接入与排障以本仓公开文档和开发资料为准。' ;;
esac

agents_file="$target_dir/AGENTS.md"
package_file="$target_dir/package.json"

if [[ -L "$agents_file" ]]; then
  printf 'Refusing to replace symlink: %s\n' "$agents_file" >&2
  exit 1
fi
[[ -f "$template" && -f "$package_file" ]] || exit 1

actual_package="$(node -e 'const fs = require("fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).name || "")' "$package_file")" || exit 1
[[ "$actual_package" == "$package" ]] || exit 1
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
input_file="$agents_file"
agents_mode=644
if [[ -f "$agents_file" ]]; then
  agents_mode="$(file_mode "$agents_file")" || exit 1
else
  input_file="$temp_dir/input.md"
  printf '# %s 开发入口\n' "$repo_name" > "$input_file"
fi

if ! begin_count="$(awk -v begin="$begin_marker" -v end="$end_marker" '
  $0 == begin {
    begin_count++
    if (state != 0) invalid = 1
    state = 1
    next
  }
  $0 == end {
    end_count++
    if (state != 1) invalid = 1
    state = 2
  }
  END {
    if (invalid || begin_count != end_count || begin_count > 1 || state == 1) exit 1
    print begin_count
  }
' "$input_file")"; then
  exit 1
fi

rendered="$temp_dir/rendered.md"
updated="$temp_dir/AGENTS.md"

awk -v repo="$repo_name" -v entry="$library_skill_entry" \
  '{ gsub(/\{\{REPO\}\}/, repo); gsub(/\{\{LIBRARY_SKILL_ENTRY\}\}/, entry); print }' \
  "$template" >"$rendered"

if [[ "$begin_count" -eq 1 ]]; then
  awk -v begin="$begin_marker" -v end="$end_marker" -v replacement="$rendered" '
    $0 == begin {
      while ((getline line < replacement) > 0) print line
      close(replacement)
      replacing = 1
      next
    }
    $0 == end && replacing {
      replacing = 0
      next
    }
    !replacing { print }
  ' "$input_file" >"$updated"
else
  awk -v replacement="$rendered" '
    !inserted && /^# / {
      print
      print ""
      while ((getline line < replacement) > 0) print line
      close(replacement)
      inserted = 1
      next
    }
    { print }
    END { if (!inserted) exit 1 }
  ' "$input_file" >"$updated"
fi

if $check_only; then
  if [[ ! -f "$agents_file" ]] || ! cmp -s "$updated" "$agents_file"; then
    printf 'AGENTS.md 共享入口缺失或偏离模板\n' >&2
    exit 1
  fi
  exit 0
fi
chmod "$agents_mode" "$updated"
mv "$updated" "$agents_file"
