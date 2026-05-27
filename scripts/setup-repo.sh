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
#      (Ruleset 要求 lint / test / build-library / build-android / build-ios
#      这 5 个 check 已经被 GitHub 索引)
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
  --allow-auto-merge=true \
  --enable-issues=true \
  >/dev/null
echo "  ✓ done"
echo ""

# ── 2. Branch Ruleset(必须 PR / 5 个 required check / 禁 force push)──
echo "→ [2/6] Branch Ruleset \"protect main\" ..."
# 先看有没有同名 ruleset(幂等性 —— 已存在则更新)
EXISTING_ID=$(gh api "repos/$FULL/rulesets" --jq '.[] | select(.name == "protect main") | .id' 2>/dev/null || echo "")
if [[ -n "$EXISTING_ID" ]]; then
  echo "  ⚠ 已有同名 ruleset (id=$EXISTING_ID),更新它"
  gh api -X PUT "repos/$FULL/rulesets/$EXISTING_ID" \
    --input "$SCRIPT_DIR/rulesets/protect-main.json" \
    >/dev/null
else
  gh api -X POST "repos/$FULL/rulesets" \
    --input "$SCRIPT_DIR/rulesets/protect-main.json" \
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

# ── 4. CodeQL Default setup ───────────────────────────────────────────
echo "→ [4/6] CodeQL Default setup(只跑 JavaScript/TypeScript)..."
# 注意:Default setup 对 polyglot repo 不友好(可能 auto-detect Java/Kotlin)
# 这里显式只 enable javascript-typescript;其他 detect 到的会 skip
gh api -X PATCH "repos/$FULL/code-scanning/default-setup" \
  -f 'state=configured' \
  -f 'query_suite=default' \
  -F 'languages[]=javascript-typescript' \
  >/dev/null || echo "  ⚠ CodeQL setup 失败(可能没有 Code scanning 权限或 repo 太新),稍后手配"
echo "  ✓ done(或跳过)"
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
echo "  □ 各 caller workflow / .pr_agent.toml / dependabot.yaml 自己 commit 进 repo"
echo "  □ 详见:https://github.com/unif-design/.github/blob/main/ONBOARDING.md"
