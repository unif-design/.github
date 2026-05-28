[← 索引](../AUTOMATION.md) · [← 发版机制](./04-release.md) · [依赖管理 (Dependabot) →](./06-dependencies.md)

---

# Branch protection(Rulesets)

### 配置位置

`Settings → Rules → Rulesets → New branch ruleset`

### 关键配置

| 字段 | 值 |
|---|---|
| Ruleset Name | `protect main`(任意)|
| Enforcement status | **Active** |
| Bypass list | 加发版用的 GitHub App(`unif-release-bot`),**mode 选 `Always`**(见下方「发版 bot 进 bypass」)|
| Target branches | **Include default branch**(自动跟随 main)|

> ⚠️ **`GITHUB_TOKEN`(`github-actions[bot]`)加不进 bypass list** —— 它不是"安装的 App",bypass 的 Apps 选择器里只有真正装到 repo 的 App(Dependabot 等),没有它。所以发版直接 push 必须靠自建 GitHub App,见下。

### Rules 勾选(只这 4 个)

- ✅ **Restrict deletions** —— 防 main 被删
- ✅ **Require a pull request before merging**(子选项:approvals = 0,单人项目 self-approve 会被堵)
  - 子选项 **Allowed merge methods** 也只勾 **Squash**(其他取消)—— 强制 main 只能接受 squash merge,双重保险(repo Settings 那层即便被改也拦得住)
- ✅ **Require status checks to pass**:
  - ✅ Require branches to be up to date
  - Required checks 加这 6 个:`actionlint`、`lint`、`test`、`build-library`、`build-android`、`build-ios`
  - **不加 `pr_agent`**(AI review 是参考性,不该 gate merge)
- ✅ **Block force pushes**

**不勾**:
- ❌ Require approvals(单人项目堵死自己)
- ❌ Restrict creations / updates(会拦 release-it bot)
- ❌ Require signed commits(没配 GPG)
- ❌ Require linear history / merge queue / signed commits(用不上)

### 发版 bot 进 bypass

发版流水线要把 `chore: release X.Y.Z` commit + tag **直接 push** 回 main(release-it 不走 PR)。Ruleset 拦一切直接 push,所以必须给发版身份开一个 bypass 口子:

| 配置点 | 值 | 为什么 |
|---|---|---|
| Bypass 对象 | 自建 GitHub App `unif-release-bot`(**不是** `github-actions[bot]`)| `GITHUB_TOKEN` 进不了 bypass(非安装 App);App 才行 |
| Bypass mode | **`Always`** | release-it **直接** push 不经 PR;选 `For pull requests` 只对"经 PR 的操作"放行,对直接 push 无效 → 仍被拦 |

App 的建/装/凭据存放、workflow 里怎么用,见 [发版机制 → push 回受保护 main](./04-release.md#push-回受保护-main--用-github-app-token)。

### 副作用

- 直接 `git push origin main` → `GH013: Repository rule violations` 拒绝
- 必须经 PR + Squash merge
- **唯一例外**:发版 App(`unif-release-bot`)在 bypass list(mode `Always`),release-it 用它现场签发的 token 直接 push release commit + tag 合法通过

### Repo Settings(General → Pull Requests)推荐勾选项

跟 Ruleset 配套,在仓库 Settings 里勾这几项:

| 选项 | 勾不勾 | 原因 |
|---|---|---|
| **Allow merge commits** | ❌ | main 上不要 `Merge branch ...` 这种垃圾 commit |
| **Allow squash merging** | ✅ | 唯一保留 —— PR squash 成 1 个 commit,跟 conventional commits 完美对齐 |
| **Allow rebase merging** | ❌ | rebase 会把 PR 多个原 commit 全部推到 main,污染历史 |
| **Allow auto-merge** | ✅ | 让 PR 等满足所有 ruleset 条件(CI 绿 + branch up-to-date 等)后自动合并 —— 是 dependabot auto-merge workflow 必备(`gh pr merge --auto` 命令要求,不勾静默失败)|
| **Default to PR branch name** | 看偏好 | branch 命名规则约束 |
| **Automatically delete head branches** | ✅ | merge 后远端 branch 自动删,repo 永远干净 |
| **Always suggest updating PR branches** | 偏好 | 提示落后的 PR rebase main(配合 ruleset 的 "branches up to date" 用)|

注意:**Auto-delete head branches 只删远端**,本地 stale branch 要自己清理,见[本地 branch 清理](#本地-branch-清理)。

---


---

[← 索引](../AUTOMATION.md) · [← 发版机制](./04-release.md) · [依赖管理 (Dependabot) →](./06-dependencies.md)
