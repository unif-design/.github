#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

# Execute the actual workflow guard against successful and failed pod installs.
awk '
  /for attempt in 1 2; do/ { in_guard = 1 }
  in_guard { sub(/^          /, ""); print }
  in_guard && /^done$/ { exit }
' "$script_dir/../templates/workflows/ci.yml" > "$workspace/guard.sh"
test -s "$workspace/guard.sh"
mkdir -p "$workspace/bin"
cat > "$workspace/bin/bundle" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'exec pod install --project-directory=ios' ]]
count=0
if [[ -f attempts ]]; then read -r count < attempts; fi
count=$((count + 1))
printf '%s\n' "$count" > attempts
if [[ "$POD_TEST_MODE" == failure ]]; then exit 42; fi
mkdir -p ios
if [[ "$POD_TEST_MODE" == prebuilt ]] || [[ "$POD_TEST_MODE" == retry && "$count" == 2 ]]; then
  printf '  - React-Core-prebuilt (0.88.0)\n' > ios/Podfile.lock
else
  printf '  - React-Core (0.88.0)\n' > ios/Podfile.lock
fi
STUB
chmod +x "$workspace/bin/bundle"

for scenario in 'prebuilt 0 1' 'retry 0 2' 'source 1 2' 'failure 42 1'; do
  read -r mode expected_status expected_attempts <<< "$scenario"
  mkdir "$workspace/$mode"
  actual=0
  (
    cd "$workspace/$mode"
    PATH="$workspace/bin:$PATH" POD_TEST_MODE="$mode" bash -e "$workspace/guard.sh"
  ) > "$workspace/$mode/output" 2>&1 || actual=$?
  [[ "$actual" == "$expected_status" ]] || {
    cat "$workspace/$mode/output"
    printf 'Unexpected status for %s: %s\n' "$mode" "$actual" >&2
    exit 1
  }
  [[ "$(cat "$workspace/$mode/attempts")" == "$expected_attempts" ]]
done
printf 'iOS prebuilt guard: 4 scenarios passed\n'
