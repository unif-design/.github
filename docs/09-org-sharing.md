[← 索引](../AUTOMATION.md) · [← PR Review (AI 辅助)](./08-pr-review.md) · [应急流程 →](./10-emergency.md)

---

# Org 级共享基础设施

`unif-design` 组织通过 GitHub 的几个机制做配置共享,**新 repo 加入 org 后基本零配置**(发版相关除外):

### 1. Org-level Secret

`unif-design` Org Settings → Secrets and variables → Actions:

| Secret | 用途 | Repository access |
|---|---|---|
| `DEEPSEEK_API_KEY` | PR Agent 调 DeepSeek API | All repositories |

新 repo 自动能用 `${{ secrets.DEEPSEEK_API_KEY }}`,**不需要每个 repo 重新配**。

### 2. `unif-design/.github` 特殊仓库(org 默认配置库)

GitHub 约定:org 下名为 `.github` 的 public 仓库里的特殊文件**自动 fallback 到所有 repo**(如果 repo 自己没同名文件)。

| 文件 | 路径 | 共享机制 |
|---|---|---|
| **PR 模板** | `.github/PULL_REQUEST_TEMPLATE.md` | 各 repo 自己有同名文件则 override,否则用 org 默认 |
| **贡献指南** | `CONTRIBUTING.md` | 同上 |
| **行为准则** | `CODE_OF_CONDUCT.md` | 同上 |
| **安全策略** | `SECURITY.md` | 同上,定义漏洞报告渠道 + 响应时间承诺 |
| **本文档**(自动化标准)| `AUTOMATION.md` | **不自动 fallback**(GitHub 只对上面几种文件做 fallback),各 repo 用链接引用 |
| **Reusable workflow** | `.github/workflows/pr-agent.yml` | 各 repo 写 5 行 caller 调用(见上节)|

### 3. Reusable Workflow

不在 fallback 清单里,但能跨 repo 调用。**写一次在 `.github`,各 repo 5 行 caller 调用**。改 reusable workflow 内容 → 立刻对所有 caller 生效(因为引用 `@main`)。

如果担心改动影响:用 git tag 引用(如 `@v1`),各 caller 自己决定何时升级。

### 4. Org-level Rulesets(需要 GitHub Team / Enterprise plan)

Team plan($4/user/月)及以上可以在 org 级配 branch protection ruleset,**一次配置全 org repo 共享**。Free plan 不支持,只能每个 repo 单独配 ruleset。

### 新 repo 接入 checklist

| 步 | 操作 | 时间 |
|---|---|---|
| 1 | 在 org 下建 repo | 1 分钟 |
| 2 | 自动获得 org 默认 PR template / CONTRIBUTING | 0 秒 |
| 3 | 加 `.github/workflows/pr-agent.yml` caller(5 行)| 30 秒 |
| 4 | 在 repo 自己 Settings → Branches 配 ruleset(Free plan)| 5 分钟 |
| 5 | 设 Squash merge default + Auto-delete head branches | 1 分钟 |
| 6 | 如果是 npm 包:配 release.yml + Trusted Publisher | 15 分钟(每个 npm 包必须自己配)|

第 4、5 步在 Team plan 下可以省(走 org-level ruleset / org Settings)。

---


---

[← 索引](../AUTOMATION.md) · [← PR Review (AI 辅助)](./08-pr-review.md) · [应急流程 →](./10-emergency.md)
