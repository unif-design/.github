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
| Bypass list | 留空(GitHub Actions bot 默认放行,直接试,不行再加 `Repository role: Admin` / `Maintain`)|
| Target branches | **Include default branch**(自动跟随 main)|

### Rules 勾选(只这 4 个)

- ✅ **Restrict deletions** —— 防 main 被删
- ✅ **Require a pull request before merging**(子选项:approvals = 0,单人项目 self-approve 会被堵)
  - 子选项 **Allowed merge methods** 也只勾 **Squash**(其他取消)—— 强制 main 只能接受 squash merge,双重保险(repo Settings 那层即便被改也拦得住)
- ✅ **Require status checks to pass**:
  - ✅ Require branches to be up to date
  - Required checks 加这 5 个:`lint`、`test`、`build-library`、`build-android`、`build-ios`
  - **不加 `pr_agent`**(AI review 是参考性,不该 gate merge)
- ✅ **Block force pushes**

**不勾**:
- ❌ Require approvals(单人项目堵死自己)
- ❌ Restrict creations / updates(会拦 release-it bot)
- ❌ Require signed commits(没配 GPG)
- ❌ Require linear history / merge queue / signed commits(用不上)

### 副作用

- 直接 `git push origin main` → `GH013: Repository rule violations` 拒绝
- 必须经 PR + Squash merge
- release-it bot 用 `GITHUB_TOKEN` push 仍能过(GitHub Actions 默认放行)

### Repo Settings(General → Pull Requests)推荐勾选项

跟 Ruleset 配套,在仓库 Settings 里勾这几项:

| 选项 | 勾不勾 | 原因 |
|---|---|---|
| **Allow merge commits** | ❌ | main 上不要 `Merge branch ...` 这种垃圾 commit |
| **Allow squash merging** | ✅ | 唯一保留 —— PR squash 成 1 个 commit,跟 conventional commits 完美对齐 |
| **Allow rebase merging** | ❌ | rebase 会把 PR 多个原 commit 全部推到 main,污染历史 |
| **Default to PR branch name** | 看偏好 | branch 命名规则约束 |
| **Automatically delete head branches** | ✅ | merge 后远端 branch 自动删,repo 永远干净 |
| **Always suggest updating PR branches** | 偏好 | 提示落后的 PR rebase main(配合 ruleset 的 "branches up to date" 用)|

注意:**Auto-delete head branches 只删远端**,本地 stale branch 要自己清理,见[本地 branch 清理](#本地-branch-清理)。

---


---

[← 索引](../AUTOMATION.md) · [← 发版机制](./04-release.md) · [依赖管理 (Dependabot) →](./06-dependencies.md)
