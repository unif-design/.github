#!/usr/bin/env bash
# 把 unif-design 下的 repo 一键配置到 org 标准。
#
# 用法:
#   ./setup-repo.sh <repo-name>
#
# 前置:
#   1. 已经 `gh auth login`,gh 当前账号是 unif-design 的 admin
#   2. 目标 repo 已经存在(没创建过先用 `gh repo create unif-design/<repo>`)
#   3. CI workflow(`.github/workflows/ci.yml`)已经在 repo 里且跑过至少一次
#      (Ruleset 要求 actionlint / lint / test / build-library / build-android / build-ios
#      这 6 个 check 已经被 GitHub 索引;ci.yml 由 sync-repo.sh 从 .github/templates 下发)
#      native 仓(umeng / hms-scan)还要 native-lint.yml 跑过一次(多 lint-cpp / lint-kotlin
#      两个 check),本脚本检测到 native-lint.yml 会自动套 8-check 版 ruleset。
#
# 跑完后还要手配:
#   - npm Trusted Publisher(在 npmjs.com 端,如果是 npm 包)
#   - GitHub Pages 第一次 deploy(若 repo 有 deploy-docs.yml,push 即触发)
#
# 幂等:重复跑同一 repo,所有 step 都是 PATCH / 创建-或-更新,不会破坏现有配置

set -euo pipefail

# ── 参数 ──────────────────────────────────────────────────────────────
ORG="unif-design"
REPO="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$REPO" ]]; then
  echo "用法: $0 <repo-name>"
  echo "  例: $0 react-native-design"
  exit 1
fi

FULL="$ORG/$REPO"
echo "→ 配置 $FULL ..."
echo ""

# ── 0. 前置检查 ───────────────────────────────────────────────────────
if ! gh auth status >/dev/null 2>&1; then
  echo "✗ gh 未登录,先 \`gh auth login\`"
  exit 1
fi

if ! gh repo view "$FULL" >/dev/null 2>&1; then
  echo "✗ repo $FULL 不存在,先 \`gh repo create $FULL --public\`"
  exit 1
fi

echo "✓ 前置检查通过"
echo ""

# ── 1. Repo 基础 settings:merge methods + auto-delete ────────────────
echo "→ [1/6] Repo Settings:Squash merge only + auto-delete branches ..."
gh repo edit "$FULL" \
  --enable-merge-commit=false \
  --enable-squash-merge=true \
  --enable-rebase-merge=false \
  --delete-branch-on-merge=true \
  --enable-auto-merge=true \
  --enable-issues=true \
  >/dev/null
echo "  ✓ done"
echo ""

# ── 2. Branch Ruleset(必须 PR / required check / 禁 force push / release-bot bypass)──
echo "→ [2/6] Branch Ruleset \"protect main\" ..."
# native 仓(有 .github/workflows/native-lint.yml)多 lint-cpp / lint-kotlin 两个 required check,
# 套 8-check 版 ruleset;其余套 6-check 版。判据 = 仓里有没有 native-lint.yml
# (它由 sync-repo.sh 仅下发给 native 仓 —— 有它 ⟺ 有那两个 check ⟺ 该用 8-check 版),自洽。
if gh api "repos/$FULL/contents/.github/workflows/native-lint.yml" >/dev/null 2>&1; then
  RULESET_FILE="$SCRIPT_DIR/rulesets/protect-main-native.json"
  echo "  · 检测到 native-lint.yml → 用 8-check ruleset(含 lint-cpp / lint-kotlin)"
else
  RULESET_FILE="$SCRIPT_DIR/rulesets/protect-main.json"
  echo "  · 无 native-lint.yml → 用 6-check ruleset"
fi
# 先看有没有同名 ruleset(幂等性 —— 已存在则更新)
EXISTING_ID=$(gh api "repos/$FULL/rulesets" --jq '.[] | select(.name == "protect main") | .id' 2>/dev/null || echo "")
if [[ -n "$EXISTING_ID" ]]; then
  echo "  ⚠ 已有同名 ruleset (id=$EXISTING_ID),更新它"
  gh api -X PUT "repos/$FULL/rulesets/$EXISTING_ID" \
    --input "$RULESET_FILE" \
    >/dev/null
else
  gh api -X POST "repos/$FULL/rulesets" \
    --input "$RULESET_FILE" \
    >/dev/null
fi
echo "  ✓ done"
echo ""

# ── 3. 安全功能:Secret scanning + Private vulnerability reporting ────
echo "→ [3/6] Security features:Secret scanning + Private vulnerability reporting ..."
gh api -X PATCH "repos/$FULL" \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled' \
  >/dev/null
gh api -X PUT "repos/$FULL/private-vulnerability-reporting" >/dev/null
echo "  ✓ done"
echo ""

# ── 4. CodeQL:显式关闭(小团队私有 RN bridge 库不上 CodeQL)──────────
echo "→ [4/6] CodeQL Default setup:显式关闭 ..."
# 决策(deep-research 结论):小团队私有 RN bridge 库不启用 CodeQL。
#   · JS/TS 层薄(主要是 native bridge 胶水),CodeQL 静态扫描安全价值低
#   · polyglot native 仓(Kotlin / ObjC / C++)Default setup 不友好 —— 会 auto-detect
#     java-kotlin / c-cpp、要 build、拖慢或失败,对 RN native bridge 实际告警价值有限
#   · 一致性:Default setup 的语言列表 GitHub 会自动重检测、在各仓漂移(详见 docs/07-security.md)
# 主动 PATCH not-configured —— 即便 GitHub 对某仓自动开启了 Default setup 也会被关掉,enforce 统一关闭。
gh api -X PATCH "repos/$FULL/code-scanning/default-setup" \
  -f 'state=not-configured' \
  >/dev/null 2>&1 && echo "  ✓ CodeQL 已关闭" || echo "  ⊘ CodeQL 本就未启用,跳过"
echo ""

# ── 5. GitHub Pages(只在仓库已有 deploy workflow 时启用)─────────────
echo "→ [5/6] GitHub Pages ..."
if gh api "repos/$FULL/contents/.github/workflows/deploy-docs.yml" >/dev/null 2>&1; then
  gh api -X POST "repos/$FULL/pages" \
    -f 'build_type=workflow' \
    >/dev/null 2>&1 || echo "  ⚠ Pages 可能已启用,跳过"
  echo "  ✓ Pages 启用,Source=GitHub Actions"
else
  echo "  ⊘ skip(repo 内无 .github/workflows/deploy-docs.yml,无需启用 Pages)"
fi
echo ""

# ── 6. About 区:Use Pages URL as website + Topics ───────────────────
echo "→ [6/6] About 区:Pages URL + Topics ..."
if gh api "repos/$FULL/pages" >/dev/null 2>&1; then
  PAGES_URL=$(gh api "repos/$FULL/pages" --jq '.html_url')
  gh repo edit "$FULL" --homepage "$PAGES_URL" >/dev/null
  echo "  ✓ Website = $PAGES_URL"
else
  echo "  ⊘ skip(无 Pages,Website 字段不动)"
fi
# Topics 不在这里硬编码 —— 各 repo 内容不同,留给手配 / repo 自己的 setup
echo ""

# ── 完成 ──────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ $FULL GitHub 端配置完成"
echo ""
echo "仍需手配:"
echo "  □ Topics(repo Settings → About → Edit topics)"
echo "  □ npm Trusted Publisher(npmjs.com → 包 Settings,如果发 npm 包)"
echo "  □ workflow / 配置文件:跑 ./scripts/sync-repo.sh $REPO 下发(本脚本只管 GitHub 端配置)"
echo "  □ 详见:https://github.com/unif-design/.github/blob/main/ONBOARDING.md"
