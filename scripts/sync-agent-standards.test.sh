#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sync_script="$script_dir/sync-agent-standards.sh"
full_sync_script="$script_dir/sync-repo.sh"
workspace="$(mktemp -d)"
target="$workspace/react-native-camera"
bad_target="$workspace/bad-marker"
duplicate_target="$workspace/duplicate-marker"
reverse_target="$workspace/reverse-marker"
symlink_target="$workspace/symlink-target"
symlink_source="$workspace/symlink-source.md"
full_target="$workspace/full-react-native-design"
full_output="$workspace/full-react-native-design-sync.log"
other_target="$workspace/example-repo"
other_output="$workspace/example-repo-sync.log"

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

trap cleanup EXIT

mkdir -p "$target" "$bad_target" "$duplicate_target" "$reverse_target" "$symlink_target" "$full_target" "$other_target"

cat >"$target/AGENTS.md" <<'EOF'
# React Native Camera

## 本仓规则

保留这段本地说明。
EOF

cat >"$target/package.json" <<'EOF'
{"name":"@unif/react-native-camera"}
EOF

# 首次接入: H1 后插入共享区块,并保留本地正文。
chmod 0600 "$target/AGENTS.md"
bash "$sync_script" react-native-camera "$target"

grep -Fq '<!-- BEGIN UNIF REACT NATIVE STANDARD -->' "$target/AGENTS.md" || fail '未插入 BEGIN marker'
grep -Fq "\`react-native-camera\`" "$target/AGENTS.md" || fail '未渲染 react-native-camera 映射'
grep -Fq "\`../skills/skills/camera/\`" "$target/AGENTS.md" || fail '未渲染 camera Skill 路径'
grep -Fq '## 本仓规则' "$target/AGENTS.md" || fail '覆盖了本地正文'
[[ "$(file_mode "$target/AGENTS.md")" == 600 ]] || fail '首次同步改变了 AGENTS.md 的 0600 权限'

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

# AGENTS.md 是 symlink 时必须拒绝,且不得替换链接或改动链接目标。
cat >"$symlink_source" <<'EOF'
# Symlink Source

保留链接目标正文。
EOF
ln -s "$symlink_source" "$symlink_target/AGENTS.md"
cat >"$symlink_target/package.json" <<'EOF'
{"name":"@unif/react-native-camera"}
EOF

before_symlink_destination="$(readlink "$symlink_target/AGENTS.md")"
before_symlink_source_hash="$(file_hash "$symlink_source")"
if bash "$sync_script" react-native-camera "$symlink_target"; then
  fail 'symlink AGENTS.md 被接受'
fi
[[ -L "$symlink_target/AGENTS.md" ]] || fail 'symlink AGENTS.md 被替换'
after_symlink_destination="$(readlink "$symlink_target/AGENTS.md")"
after_symlink_source_hash="$(file_hash "$symlink_source")"
if [[ "$before_symlink_destination" != "$after_symlink_destination" ]]; then
  fail 'symlink AGENTS.md 的链接目标被改动'
fi
if [[ "$before_symlink_source_hash" != "$after_symlink_source_hash" ]]; then
  fail 'symlink AGENTS.md 指向的文件被改动'
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

# 目标仓通过全量同步时也必须注入正确共享区块,并保留 marker 外正文。
cat >"$full_target/AGENTS.md" <<'EOF'
# React Native Design

## 本仓规则

保留 Design 本地正文。
EOF

cat >"$full_target/package.json" <<'EOF'
{"name":"@unif/react-native-design"}
EOF

if ! bash "$full_sync_script" react-native-design "$full_target" >"$full_output"; then
  fail '目标仓全量同步退出非零'
fi
grep -Fq '<!-- BEGIN UNIF REACT NATIVE STANDARD -->' "$full_target/AGENTS.md" || fail '目标仓全量同步未插入共享 marker'
grep -Fq "\`react-native-design\`" "$full_target/AGENTS.md" || fail '目标仓全量同步未渲染 repo 映射'
grep -Fq "\`../skills/skills/design/\`" "$full_target/AGENTS.md" || fail '目标仓全量同步未渲染 Design Skill'
grep -Fq '## 本仓规则' "$full_target/AGENTS.md" || fail '目标仓全量同步覆盖了本地标题'
grep -Fq '保留 Design 本地正文。' "$full_target/AGENTS.md" || fail '目标仓全量同步覆盖了本地正文'

# 非四仓仍可使用全量同步,但不得注入 React Native 共享 Agent 区块。
cat >"$other_target/AGENTS.md" <<'EOF'
# Example Repo

## 本仓规则

保留非目标仓本地正文。
EOF

cat >"$other_target/package.json" <<'EOF'
{"name":"example-repo"}
EOF

if ! bash "$full_sync_script" example-repo "$other_target" >"$other_output"; then
  fail '非目标仓全量同步退出非零'
fi
if grep -Fq '<!-- BEGIN UNIF REACT NATIVE STANDARD -->' "$other_target/AGENTS.md"; then
  fail '非目标仓被插入共享 marker'
fi
grep -Fq '## 本仓规则' "$other_target/AGENTS.md" || fail '非目标仓本地标题被覆盖'
grep -Fq '保留非目标仓本地正文。' "$other_target/AGENTS.md" || fail '非目标仓本地正文被覆盖'
grep -Fq '非共享 Agent 标准目标仓,跳过 AGENTS.md' "$other_output" || fail '非目标仓未明确报告跳过共享 Agent 标准'

printf 'PASS: sync-agent-standards contract\n'
