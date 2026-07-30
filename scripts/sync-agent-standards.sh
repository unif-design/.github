#!/usr/bin/env bash

set -euo pipefail

begin_marker='<!-- BEGIN UNIF REACT NATIVE STANDARD -->'
end_marker='<!-- END UNIF REACT NATIVE STANDARD -->'
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="$script_dir/../templates/AGENTS.md"

usage() {
  printf 'Usage: %s <repo-name> [target-path]\n' "${0##*/}" >&2
  exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage

repo_name="$1"
target_dir="${2:-$PWD}"

case "$repo_name" in
  react-native-camera) skill=camera; package='@unif/react-native-camera' ;;
  react-native-design) skill=design; package='@unif/react-native-design' ;;
  react-native-hms-scan) skill=hms-scan; package='@unif/react-native-hms-scan' ;;
  react-native-umeng) skill=umeng-share; package='@unif/react-native-umeng' ;;
  *) exit 2 ;;
esac

agents_file="$target_dir/AGENTS.md"
package_file="$target_dir/package.json"

[[ -f "$template" && -f "$agents_file" && -f "$package_file" ]] || exit 1

actual_package="$(node -e 'const fs = require("fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).name || "")' "$package_file")" || exit 1
[[ "$actual_package" == "$package" ]] || exit 1

begin_count="$(grep -Fxc "$begin_marker" "$agents_file" || true)"
end_count="$(grep -Fxc "$end_marker" "$agents_file" || true)"
if [[ "$begin_count" != "$end_count" || "$begin_count" -gt 1 ]]; then
  exit 1
fi

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/sync-agent-standards.XXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT
rendered="$temp_dir/rendered.md"
updated="$temp_dir/AGENTS.md"

awk -v repo="$repo_name" -v skill_name="$skill" \
  '{ gsub(/\{\{REPO\}\}/, repo); gsub(/\{\{SKILL\}\}/, skill_name); print }' \
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
  ' "$agents_file" >"$updated"
else
  awk -v replacement="$rendered" '
    !inserted && /^# / {
      print
      while ((getline line < replacement) > 0) print line
      close(replacement)
      inserted = 1
      next
    }
    { print }
    END { if (!inserted) exit 1 }
  ' "$agents_file" >"$updated"
fi

mv "$updated" "$agents_file"
