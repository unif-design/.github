#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sync_script="$script_dir/sync-agent-standards.sh"
workspace="$(mktemp -d)"
target="$workspace/react-native-camera"
bad_target="$workspace/bad-marker"
duplicate_target="$workspace/duplicate-marker"
reverse_target="$workspace/reverse-marker"

cleanup() {
  rm -rf "$workspace"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

file_hash() {
  shasum "$1" | awk '{print $1}'
}

trap cleanup EXIT

mkdir -p "$target" "$bad_target" "$duplicate_target" "$reverse_target"

cat >"$target/AGENTS.md" <<'EOF'
# React Native Camera

## 本仓规则

保留这段本地说明。
EOF

cat >"$target/package.json" <<'EOF'
{"name":"@unif/react-native-camera"}
EOF

# 首次接入: H1 后插入共享区块,并保留本地正文。
bash "$sync_script" react-native-camera "$target"

grep -Fq '<!-- BEGIN UNIF REACT NATIVE STANDARD -->' "$target/AGENTS.md" || fail '未插入 BEGIN marker'
grep -Fq "\`react-native-camera\`" "$target/AGENTS.md" || fail '未渲染 react-native-camera 映射'
grep -Fq "\`../skills/skills/camera/\`" "$target/AGENTS.md" || fail '未渲染 camera Skill 路径'
grep -Fq '## 本仓规则' "$target/AGENTS.md" || fail '覆盖了本地正文'

# 已接入时应原位替换已有共享区块。
awk '{ gsub(/`react-native-camera`/, "`stale-camera`"); print }' "$target/AGENTS.md" >"$target/AGENTS.md.next"
mv "$target/AGENTS.md.next" "$target/AGENTS.md"
bash "$sync_script" react-native-camera "$target"
grep -Fq "\`react-native-camera\`" "$target/AGENTS.md" || fail '未替换已有共享区块'
if grep -Fq "\`stale-camera\`" "$target/AGENTS.md"; then
  fail '保留了过期的共享区块内容'
fi

# 重复同步必须完全幂等。
before_idempotent_hash="$(file_hash "$target/AGENTS.md")"
bash "$sync_script" react-native-camera "$target"
after_idempotent_hash="$(file_hash "$target/AGENTS.md")"
if [[ "$before_idempotent_hash" != "$after_idempotent_hash" ]]; then
  fail '重复同步改变了 AGENTS.md'
fi

# 缺少 END marker 时必须拒绝写入。
cat >"$bad_target/AGENTS.md" <<'EOF'
# Bad Marker

<!-- BEGIN UNIF REACT NATIVE STANDARD -->

## 本仓规则
EOF

cat >"$bad_target/package.json" <<'EOF'
{"name":"@unif/react-native-camera"}
EOF

before_bad_marker_hash="$(file_hash "$bad_target/AGENTS.md")"
if bash "$sync_script" react-native-camera "$bad_target"; then
  fail '只含 BEGIN marker 的 AGENTS.md 被接受'
fi
after_bad_marker_hash="$(file_hash "$bad_target/AGENTS.md")"
if [[ "$before_bad_marker_hash" != "$after_bad_marker_hash" ]]; then
  fail '坏 marker 被拒绝前仍写入了 AGENTS.md'
fi

# 重复 marker 必须在写入前拒绝。
cat >"$duplicate_target/AGENTS.md" <<'EOF'
# Duplicate Marker

<!-- BEGIN UNIF REACT NATIVE STANDARD -->
first
<!-- END UNIF REACT NATIVE STANDARD -->

<!-- BEGIN UNIF REACT NATIVE STANDARD -->
second
<!-- END UNIF REACT NATIVE STANDARD -->
EOF

cat >"$duplicate_target/package.json" <<'EOF'
{"name":"@unif/react-native-camera"}
EOF

before_duplicate_hash="$(file_hash "$duplicate_target/AGENTS.md")"
if bash "$sync_script" react-native-camera "$duplicate_target"; then
  fail '重复 marker 的 AGENTS.md 被接受'
fi
after_duplicate_hash="$(file_hash "$duplicate_target/AGENTS.md")"
if [[ "$before_duplicate_hash" != "$after_duplicate_hash" ]]; then
  fail '重复 marker 被拒绝前仍写入了 AGENTS.md'
fi

# END 在 BEGIN 前必须在写入前拒绝。
cat >"$reverse_target/AGENTS.md" <<'EOF'
# Reverse Marker

<!-- END UNIF REACT NATIVE STANDARD -->
stale
<!-- BEGIN UNIF REACT NATIVE STANDARD -->
EOF

cat >"$reverse_target/package.json" <<'EOF'
{"name":"@unif/react-native-camera"}
EOF

before_reverse_hash="$(file_hash "$reverse_target/AGENTS.md")"
if bash "$sync_script" react-native-camera "$reverse_target"; then
  fail '倒序 marker 的 AGENTS.md 被接受'
fi
after_reverse_hash="$(file_hash "$reverse_target/AGENTS.md")"
if [[ "$before_reverse_hash" != "$after_reverse_hash" ]]; then
  fail '倒序 marker 被拒绝前仍写入了 AGENTS.md'
fi

# repo-name 与 package.json#name 不一致时必须拒绝写入。
cat >"$target/package.json" <<'EOF'
{"name":"@unif/react-native-design"}
EOF

before_package_mismatch_hash="$(file_hash "$target/AGENTS.md")"
if bash "$sync_script" react-native-camera "$target"; then
  fail 'package.json 名称不匹配时仍执行同步'
fi
after_package_mismatch_hash="$(file_hash "$target/AGENTS.md")"
if [[ "$before_package_mismatch_hash" != "$after_package_mismatch_hash" ]]; then
  fail '包名不匹配被拒绝前仍写入了 AGENTS.md'
fi

# 四仓固定映射都必须渲染对应 repo 与 Skill,并通过 package identity 校验。
for mapping in \
  'react-native-camera:@unif/react-native-camera:camera' \
  'react-native-design:@unif/react-native-design:design' \
  'react-native-hms-scan:@unif/react-native-hms-scan:hms-scan' \
  'react-native-umeng:@unif/react-native-umeng:umeng-share'; do
  IFS=':' read -r repo package skill <<<"$mapping"
  mapping_target="$workspace/$repo"
  mkdir -p "$mapping_target"
  printf '# %s\n\n本仓内容。\n' "$repo" >"$mapping_target/AGENTS.md"
  printf '{"name":"%s"}\n' "$package" >"$mapping_target/package.json"

  bash "$sync_script" "$repo" "$mapping_target"
  grep -Fq "\`$repo\`" "$mapping_target/AGENTS.md" || fail "$repo 未渲染 repo 映射"
  grep -Fq "\`../skills/skills/$skill/\`" "$mapping_target/AGENTS.md" || fail "$repo 未渲染 Skill 映射"
done

printf 'PASS: sync-agent-standards contract\n'
