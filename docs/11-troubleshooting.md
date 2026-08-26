[← 索引](../AUTOMATION.md) · [← 应急流程](./10-emergency.md) · [配置文件清单 + 不要做的事 →](./12-reference.md)

---

# 排查常见报错

### `Not authenticated with npm. Please npm login` (release-it 报)

**原因**:release-it 跑 `npm whoami` 预检查,OIDC 没持久登录,直接 abort。

**修法**:`package.json#release-it.npm.skipChecks: true`。已配,这条不该再出现。

---

### `Repository rule violations found for refs/heads/main` (GH013)

**原因**:试图直接 push 到 main,被 branch protection ruleset 拦。

**修法**:走 PR + Squash merge。**正确的反馈,不是 bug**。

如果是**发版 bot** 推 release commit 被拦:用自建 GitHub App 现场签发的 token push,且把该 App 加进 ruleset Bypass list、**mode 选 `Always`**(不是 `For pull requests`,直接 push 不经 PR)。`GITHUB_TOKEN` / `github-actions[bot]` 加不进 bypass。完整方案见 [发版机制 → push 回受保护 main](./04-release.md#push-回受保护-main--用-github-app-token)。

---

### `release.yml` if 表达式含冒号导致 workflow 不注册

**现象**:改完 `release.yml` 后,Actions 列表里**根本看不到** Release 这个 workflow,push / 手动都不触发 —— 像是没生效。点进文件 GitHub 顶部报 `mapping values are not allowed here`。

**根因**:job 级 `if` 写成 plain scalar 且表达式里含 `'chore: release'`,这个**冒号**在 YAML plain scalar 中被当成 mapping(键值对)的分隔符,整个 `release.yml` YAML 解析失败。**YAML 解析失败的 workflow GitHub 直接不注册**,所以列表里看不到、也不触发。

```yaml
# ❌ 冒号被 YAML 当 mapping 分隔符,解析炸
if: ${{ github.event_name == 'workflow_dispatch' || !startsWith(github.event.head_commit.message, 'chore: release') }}

# ✅ 整个 ${{ }} 套一层 YAML 双引号,引号内冒号不再解析为 mapping
if: "${{ github.event_name == 'workflow_dispatch' || !startsWith(github.event.head_commit.message, 'chore: release') }}"
```

**通用教训**:workflow 里任何含 `: `(冒号+空格)或其它 YAML 特殊字符的 `if` / 表达式 / 字符串,都要套引号。这类 YAML bug 光靠 lint js/ts 的 CI 拦不住 —— 加 [actionlint](./03-ci.md#actionlint--防-workflow-yaml--shell-bug) 在 PR 阶段就能挡。

---

### 发版死循环(无限刷版本号)

**现象**:合并一个 PR 后,Release workflow 一遍遍自己触发自己,版本号止不住地往上刷(react-native-design 实测刷出 `0.4.0`~`0.4.33` 几十个空版本)。

**根因**:release-it 推回 main 的 `chore: release` commit 改了 `package.json`,命中 `release.yml` 的 `paths:`(含 `package.json`)→ 再次触发 release.yml → 再发再 push → 死循环。

**关键反直觉点**:这个循环是**修好 App token push 之后**才出现的 —— 之前 release commit 的 push 被 ruleset 拦着根本推不上去,所以没循环。**"让 CI 写回受保护分支" 和 "防 CI 写回触发自己" 必须成对做**,只做前者必炸。

**应急止血**(循环正在跑时,从快到慢):

1. **最快**:GitHub → Actions → 左侧选 Release workflow → 右上 `···` → **Disable workflow**(立刻切断触发,止血后再修)
2. 或者 cancel 当前正在跑的那个 run(只能挡这一轮,下一轮 push 又会触发)
3. 修好三道防线(下方)后,`···` → **Enable workflow** 恢复

**根治 —— 三道防线**(见 [发版机制 → 防自触发死循环](./04-release.md#防自触发死循环)):
1. release commit message 带 `[skip ci]`(`release-it.git.commitMessage`)
2. job 级 `if` 跳过 `chore: release` 开头的 push
3. `concurrency: { group: release, cancel-in-progress: false }`

---

### `scopeManager.addGlobals is not a function`(ESLint 报)

**原因**:yarn.lock 把 eslint 升到了 10.x,但代码用旧 plugin 期望 eslint 9 的 API。人工升级时如果没有把 eslint 与 plugin 当成兼容组合核对，`yarn install` 可能解析出不匹配的版本。

**修法**:从最新 main 重新创建人工升级分支，恢复 manifest / lockfile 后显式选择兼容版本，再运行 `yarn install`、lint、typecheck 和 test；不要手改 lockfile。

---

### `Cannot find name 'window'` / `Property 'clipboard' does not exist on type 'Navigator'`(`yarn prepare` 在 CI 失败)

**原因**:子项目(如 `website/` docs 站)用了 DOM API,但主项目 `tsconfig.json` 的 `lib: ["ESNext"]` 没含 `DOM`。问题是 `tsconfig.build.json` 自己定义的 `exclude` **覆盖**(不是合并)父 tsconfig 的 `exclude`,即使父排了 `website`,build.json 也丢。

**修法**:`tsconfig.build.json` 的 `exclude` 数组里**显式加** `website`(或任何子项目目录):

```json
{
  "extends": "./tsconfig",
  "exclude": ["example", "lib", "website"]
}
```

**通用教训**:TypeScript 的 `exclude` 字段在 extends 时是**覆盖**语义,不是合并。任何子 tsconfig 自己写 `exclude` 就必须 mirror 父全部 exclude 项。

---

### `commitlint` 报 `subject must not be sentence-case, start-case, pascal-case, upper-case`

**原因**:commit message subject 含**大写英文专有名词**。`commitlint/config-conventional` 默认规则要求 subject 全小写。

**踩坑案例**:
- ❌ `feat(components): Empty 加 icon prop`(组件名 `Empty` 大写)
- ✅ `feat(components): empty 加 icon prop`

**修法**:subject 全小写。组件名 / 类名 / Pascal-case 名字在 subject 里写小写,需要原名可以放 body / footer。或者配 `subject-case: [0]` 关掉规则(不推荐,大部分项目坚持惯例)。

---

### CodeQL Default setup 跑了未勾选的语言(polyglot repo 踩坑)→ 已决定关闭 CodeQL

**根因**:Default setup 的 Language auto-detection 是**强制行为**,扫描 repo 内**所有 detect 到**的语言,UI 上 deselect checkbox **对 auto-detected 语言无效**。典型表现(RN 项目):`example/android/` 的 Kotlin 样板被 auto-detect → java-kotlin job `No build command found` 失败;design 的 Gemfile 被检测到 → 自动加回 `ruby`,各仓覆盖面漂移。

**最终决策(2026-06):四仓统一关闭 CodeQL**,不再跟 Default setup 的 auto-detect 较劲。理由:小团队私有 RN bridge 库 JS/TS 层薄、CodeQL 安全价值低,polyglot 仓维护成本 > 收益。详见 [07-security.md](07-security.md)。`setup-repo.sh [4/6]` 已改成主动 PATCH `not-configured` enforce 关闭。

> 备选(将来真要上代码扫描):**单仓**切 **Advanced setup** —— 自己写 `.github/workflows/codeql.yml`,显式 matrix `language: javascript-typescript`,GitHub 不再 auto-detect。

---

### `release-it --dry-run` 改了 `package.json` 的 version

**预期行为,不是 bug**。release-it 的 dry-run 模式**只跳过**外部副作用(npm publish / git push / GH Release),但**真跑** `npm version X.Y.Z`,会改 `package.json` 的 version 字段。

**修法**:dry-run 后还原:
```sh
git checkout -- package.json
```

dry-run 完别忘了还原,不然下一次 commit 会带上意外的 version bump。

---

### Release workflow 跑了但没发版

**正常,不是 bug**。原因:最新 commit 是 `chore:` / `docs:` 等非 release-worthy 前缀,release-it 看到"无可发布变更"exit 0。

如果**应该发版但没发**:确认 commit 前缀是不是 `feat:` / `fix:` / 含 `BREAKING CHANGE:`。是的话看 release-it 日志,可能是 conventional-changelog plugin 解析出了问题。

---

### npm publish 失败 `403 Forbidden`

**原因**:Trusted Publisher 配置错。

**Checklist**:
- npm 包 Settings → Publishing access → Trusted Publishers 里 `workflow filename` 是否填的 `release.yml`(只填文件名,不带 `.github/workflows/` 前缀)
- `repository` / `organization` 名字是否正确
- workflow `permissions.id-token: write` 是否配了
- npm CLI 版本:run 日志看 `npm --version` ≥ 11.5.1

---

### `This branch is out-of-date with the base branch`(PR 上)

**原因**:Ruleset 配了 `Require branches to be up to date`,PR 落后于 main HEAD,必须先同步才能合。

**修法**:UI 点 **Update with rebase** 按钮(推荐,线性历史)，或在本地 `git fetch origin` 后把分支 rebase 到 `origin/main` 并重新推送。

---


---

[← 索引](../AUTOMATION.md) · [← 应急流程](./10-emergency.md) · [配置文件清单 + 不要做的事 →](./12-reference.md)
