#!/usr/bin/env bash
# 把 unif-design/.github 的 templates/ 同步到目标 repo 工作树。
#
# 跟 setup-repo.sh 分工:
#   - setup-repo.sh —— 配 GitHub 端(merge methods / ruleset / security / 关 CodeQL / Pages),走 gh api
#   - sync-repo.sh  —— 下发 repo 内的 workflow + 配置文件(本脚本),走文件拷贝 + 变量替换
#
# 用法:
#   ./sync-repo.sh <repo-name> [target-repo-path]
#     <repo-name>        目标 repo 名(如 react-native-design),用于 {{REPO}} / URL 替换
#     [target-repo-path] 目标 repo 本地工作树路径,默认 ../<repo-name>(兄弟目录)
#
# 行为:
#   - 只改目标 repo 的【工作树】,不 git add / commit / push —— 改动留给你 review,各仓自己提 PR。
#   - 幂等:可反复跑。
#
# 覆盖策略(关键):
#   - 强制覆盖(统一标准,不允许单仓 drift):
#       .github/workflows/{ci,release,pr-title,pr-agent,dependabot-auto-merge}.yml
#       lefthook.yml / SECURITY.md
#       .github/ISSUE_TEMPLATE/{bug_report,config}.yml
#   - 仅当目标【不存在】时创建(保留各仓 repo 特化,不覆盖):
#       .github/PULL_REQUEST_TEMPLATE.md(各仓有特化 checklist,如 umeng 微信分享项)
#       .github/dependabot.yaml(各仓有特化分组)
#       .pr_agent.toml(各仓有特化 review 规则)
#       .github/ISSUE_TEMPLATE/feature_request.yml(各仓有特化字段)
#   - 条件分发:
#       deploy-docs.yml 仅当目标有 website/ 目录
#       native-lint.yml + nightly-build-check.yml + .clang-format 仅当目标有手写 native 源码(.kt/.mm)
#   - release.yml 的 on.push.paths:目标有 *.podspec → native paths,否则 JS-only paths
#
# 变量替换:
#   {{REPO}}      → repo 名
#   {{NPM_PKG}}   → npm 包名(从目标 package.json 的 "name" 读;读不到 fallback @unif/<repo>)
#   {{PAGES_URL}} → https://unif-design.github.io/<repo>/

set -euo pipefail

# ── 参数 ──────────────────────────────────────────────────────────────
REPO="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/templates"

if [[ -z "$REPO" ]]; then
  echo "用法: $0 <repo-name> [target-repo-path]"
  echo "  例: $0 react-native-design"
  exit 1
fi

TARGET="${2:-$(cd "$SCRIPT_DIR/../.." && pwd)/$REPO}"

if [[ ! -d "$TARGET" ]]; then
  echo "✗ 目标 repo 路径不存在: $TARGET"
  echo "  传第二参数指定路径,或确保 ../$REPO 存在。"
  exit 1
fi
if [[ ! -d "$TEMPLATES_DIR" ]]; then
  echo "✗ templates 目录不存在: $TEMPLATES_DIR"
  exit 1
fi

# ── 解析变量 ──────────────────────────────────────────────────────────
# NPM_PKG:优先从目标 package.json 的 "name" 字段读真实包名
NPM_PKG=""
if [[ -f "$TARGET/package.json" ]]; then
  NPM_PKG="$(node -e "try{process.stdout.write(require('$TARGET/package.json').name||'')}catch(e){}" 2>/dev/null || true)"
fi
if [[ -z "$NPM_PKG" ]]; then
  NPM_PKG="@unif/$REPO"
fi
PAGES_URL="https://unif-design.github.io/$REPO/"

# 目标是否为 native 仓(有 *.podspec) / 是否有 website
HAS_PODSPEC=false
if ls "$TARGET"/*.podspec >/dev/null 2>&1; then HAS_PODSPEC=true; fi
HAS_WEBSITE=false
if [[ -d "$TARGET/website" ]]; then HAS_WEBSITE=true; fi

# 是否有「手写 native 源码」—— 决定 native-lint.yml / .clang-format / nightly-build-check.yml 下不下发。
# 只看库本体的 android/src + ios/(crnl 布局下 example app 的 native 在 example/ 下,不会误命中)。
# 判据用源码而非 *.podspec:design 纯 JS 但可能有壳 podspec,而 native lint 只对真有 .kt/.mm 的仓有意义。
HAS_NATIVE_SRC=false
if find "$TARGET/android/src" "$TARGET/ios" -type f \
     \( -name '*.kt' -o -name '*.kts' -o -name '*.mm' -o -name '*.m' -o -name '*.cpp' -o -name '*.h' \) \
     2>/dev/null | grep -q .; then
  HAS_NATIVE_SRC=true
fi

echo "→ 同步 templates → $REPO"
echo "  target     : $TARGET"
echo "  npm pkg    : $NPM_PKG"
echo "  pages url  : $PAGES_URL"
echo "  podspec    : $HAS_PODSPEC"
echo "  native src : $HAS_NATIVE_SRC (有 .kt/.mm → 下发 native-lint + .clang-format + nightly)"
echo "  website    : $HAS_WEBSITE"
echo ""

# ── 工具函数 ──────────────────────────────────────────────────────────
# 变量替换:stdin → stdout
subst() {
  sed -e "s|{{REPO}}|$REPO|g" \
      -e "s|{{NPM_PKG}}|$NPM_PKG|g" \
      -e "s|{{PAGES_URL}}|$PAGES_URL|g"
}

# 强制写(替换变量后覆盖目标)
# render <template-rel-path> <target-rel-path>
render() {
  local src="$TEMPLATES_DIR/$1"
  local dst="$TARGET/$2"
  mkdir -p "$(dirname "$dst")"
  subst < "$src" > "$dst"
  echo "  ✓ $2"
}

# 仅当目标不存在时写(保留 repo 特化)
# render_if_absent <template-rel-path> <target-rel-path>
render_if_absent() {
  local dst="$TARGET/$2"
  if [[ -e "$dst" ]]; then
    echo "  ⊘ $2(已存在,保留 repo 特化,跳过)"
    return
  fi
  render "$1" "$2"
}

# 删历史遗留的旧名文件(模板改名后旧文件不会自动消失,留着会双触发 / drift)
# prune_stale <target-rel-path>
prune_stale() {
  local dst="$TARGET/$1"
  if [[ -e "$dst" ]]; then
    if git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 && \
       git -C "$TARGET" ls-files --error-unmatch "$1" >/dev/null 2>&1; then
      git -C "$TARGET" rm -q "$1"   # git 跟踪的走 git rm(记成 rename)
    else
      rm -f "$dst"
    fi
    echo "  ✗ $1(旧名文件,已删除)"
  fi
}

# ── 0. 清理历史遗留旧名(模板改名后的 stale 文件)────────────────────
echo "→ [0] 清理旧名文件"
# dependabot-automerge.yml(无连字符)→ 已统一为 dependabot-auto-merge.yml。
# 留着会跟新名文件双触发(每个 dependabot PR 跑两遍 auto-merge)。
prune_stale .github/workflows/dependabot-automerge.yml
echo ""

# ── 1. 强制覆盖的 workflow / 配置文件 ────────────────────────────────
echo "→ [1] 强制覆盖(统一标准)"
render workflows/ci.yml                       .github/workflows/ci.yml
render workflows/pr-title.yml                 .github/workflows/pr-title.yml
render workflows/pr-agent.yml                 .github/workflows/pr-agent.yml
render workflows/dependabot-auto-merge.yml    .github/workflows/dependabot-auto-merge.yml
render lefthook.yml                           lefthook.yml
render SECURITY.md                            SECURITY.md
render ISSUE_TEMPLATE/bug_report.yml          .github/ISSUE_TEMPLATE/bug_report.yml
render ISSUE_TEMPLATE/config.yml              .github/ISSUE_TEMPLATE/config.yml
echo ""

# ── 2. release.yml(按 native/JS 决定 paths)────────────────────────
echo "→ [2] release.yml(按 native/JS 注入 paths)"
# 把多行 paths 写进临时文件,再让 awk 命中 {{RELEASE_PATHS}} 时 cat 进来
# —— 不经 awk -v 传多行串(BSD awk 会报 "newline in string")。
PATHS_TMP="$(mktemp)"
trap 'rm -f "$PATHS_TMP"' EXIT
if $HAS_PODSPEC; then
  printf "%s\n" \
    "      - 'src/**'" \
    "      - 'ios/**'" \
    "      - 'android/**'" \
    "      - '*.podspec'" \
    "      - 'package.json'" \
    "      - 'yarn.lock'" > "$PATHS_TMP"
else
  printf "%s\n" \
    "      - 'src/**'" \
    "      - 'scripts/**'" \
    "      - 'package.json'" \
    "      - 'yarn.lock'" > "$PATHS_TMP"
fi
mkdir -p "$TARGET/.github/workflows"
subst < "$TEMPLATES_DIR/workflows/release.yml" \
  | awk -v pf="$PATHS_TMP" '
      # 只替换首个 {{RELEASE_PATHS}} 标记行(防 header 注释里再次出现导致重复注入)
      !done && index($0, "{{RELEASE_PATHS}}") {
        while ((getline line < pf) > 0) print line
        close(pf)
        done = 1
        next
      }
      { print }
    ' > "$TARGET/.github/workflows/release.yml"
echo "  ✓ .github/workflows/release.yml ($([ "$HAS_PODSPEC" = true ] && echo native || echo JS-only) paths)"
echo ""

# ── 3. deploy-docs.yml(仅有 website 的仓)────────────────────────────
echo "→ [3] deploy-docs.yml(条件分发)"
if $HAS_WEBSITE; then
  render workflows/deploy-docs.yml            .github/workflows/deploy-docs.yml
else
  echo "  ⊘ 目标无 website/,跳过 deploy-docs.yml"
fi
echo ""

# ── 3b. native lint / nightly(仅有手写 native 源码的仓)────────────────
echo "→ [3b] native lint / nightly build-check(条件分发)"
if $HAS_NATIVE_SRC; then
  # native-lint.yml 是 required check —— 配套的 lint-cpp/lint-kotlin 会被 setup-repo.sh
  # 自动加进 8-check ruleset。.clang-format 放仓库根,clang-format 自动发现。
  render workflows/native-lint.yml            .github/workflows/native-lint.yml
  render workflows/nightly-build-check.yml    .github/workflows/nightly-build-check.yml
  render .clang-format                        .clang-format
else
  echo "  ⊘ 目标无 native 源码(.kt/.mm),跳过 native-lint / nightly / .clang-format"
fi
echo ""

# ── 4. 仅缺时创建(保留 repo 特化)───────────────────────────────────
echo "→ [4] 仅当不存在时创建(保留 repo 特化)"
render_if_absent PULL_REQUEST_TEMPLATE.md          .github/PULL_REQUEST_TEMPLATE.md
render_if_absent dependabot.yaml                   .github/dependabot.yaml
render_if_absent pr_agent.toml                     .pr_agent.toml
render_if_absent ISSUE_TEMPLATE/feature_request.yml .github/ISSUE_TEMPLATE/feature_request.yml
echo ""

# ── 4b. 校验 package.json 的 workflow 依赖配置(sync 不改 package.json,只报警)──
# workflow 文件同步过去了,但它运行时依赖 package.json 里的配置 —— 那些是各仓特化、sync 故意不碰:
#   ci.yml / nightly 的 `yarn turbo run build:*`      → devDep turbo
#   release.yml 的 `npx release-it`(npm OIDC publish) → release-it 配置 + npm.skipChecks + conventional-changelog plugin
# 脚手架不全的新仓(如当初 hms-scan 缺 turbo / release-it)会缺这些 → workflow 跑起来才报错。
# 这里在 sync 时提前校验 + 报警,免得等 CI 一个个挂才发现。
echo "→ [4b] 校验 package.json 的 workflow 依赖配置"
if [[ -f "$TARGET/package.json" ]]; then
  node -e '
    const p = require(process.argv[1]);
    const dd = p.devDependencies || {};
    const ri = p["release-it"];
    const w = [];
    if (!dd.turbo) w.push("缺 devDep turbo —— ci.yml / nightly 的 yarn turbo run build:* 会失败");
    if (!ri) w.push("缺 release-it 配置 —— release.yml 用默认,npm OIDC 被 whoami 预检查挡(Not authenticated)");
    else if (!(ri.npm && ri.npm.skipChecks === true)) w.push("release-it.npm.skipChecks 未开 —— npm Trusted Publishing(OIDC)会被 whoami 预检查挡");
    if (!dd["@release-it/conventional-changelog"]) w.push("缺 devDep @release-it/conventional-changelog —— release-it 算 changelog 的 plugin");
    if (w.length) { console.log("  ⚠ package.json 缺 workflow 依赖配置(sync 不改 package.json,需手动补齐):"); w.forEach(x => console.log("    ✗ " + x)); }
    else console.log("  ✓ turbo / release-it(skipChecks)/ conventional-changelog 齐全");
  ' "$TARGET/package.json" || echo "  ⚠ package.json 解析失败,跳过校验"
else
  echo "  ⊘ 目标无 package.json,跳过"
fi
echo ""

# ── 5. 报告 diff(不 commit 不 push)─────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 同步完成(未 commit / 未 push)。改动:"
echo ""
if git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$TARGET" status --short
  echo ""
  git -C "$TARGET" diff --stat
else
  echo "  (目标不是 git 仓库,无法显示 diff)"
fi
echo ""
echo "下一步:在 $TARGET 里 review 改动,自己 commit + 开 PR。"
