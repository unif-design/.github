[← 索引](../AUTOMATION.md) · [← 排查常见报错](./11-troubleshooting.md)

---

# 配置文件清单

| 文件 | 作用 |
|---|---|
| `.github/workflows/ci.yml` | CI 主流程,PR + push:main 时跑 lint/test/build×3 |
| `.github/workflows/release.yml` | 发版流水线,push:main 命中 paths 或手动触发 |
| `.github/actions/setup/action.yml` | composite action,Node + yarn install + cache,被两个 workflow 复用 |
| `.github/PULL_REQUEST_TEMPLATE.md` | PR template,自动套到所有新 PR |
| `.github/dependabot.yaml` | Dependabot 配置(weekly npm + monthly actions + group)|
| `package.json#release-it` | release-it 配置(commit msg / tag / npm publish / GH release)|
| `package.json#release-it.plugins.@release-it/conventional-changelog` | changelog 生成 + 落盘 `CHANGELOG.md` |
| `package.json#commitlint` | commit msg 校验规则(`@commitlint/config-conventional`)|
| `package.json#jest` | jest preset + `testEnvironment: node` 覆盖 |
| `lefthook.yml` | git hooks:pre-commit 跑 eslint + tsc,commit-msg 跑 commitlint |
| `GitHub Settings → Rules → Rulesets` | main branch protection(UI 配,不在仓库)|
| `GitHub Settings → General → Pull Requests` | Squash merge default + auto-delete head branches(UI 配)|
| `npmjs.com → 包 Settings → Publishing access → Trusted Publishers` | npm OIDC trusted publisher 绑定(UI 配)|
| `.github/workflows/pr-agent.yml`(各 caller repo) | PR Agent caller workflow,5 行调用 org reusable |
| `.pr_agent.toml`(各 caller repo 根目录) | PR Agent 项目特有 prompt(可选)|
| `unif-design/.github/.github/workflows/pr-agent.yml` | **Org 级** PR Agent reusable workflow,模型 + DeepSeek key + 通用 prompt |
| `unif-design/.github/.github/PULL_REQUEST_TEMPLATE.md` | **Org 级**默认 PR 模板 |
| `unif-design/.github/CONTRIBUTING.md` | **Org 级**通用贡献指南 |
| `unif-design/.github/AUTOMATION.md` | **本文档** —— org 自动化标准 |
| `GitHub Org Settings → Secrets → DEEPSEEK_API_KEY` | **Org 级**密钥,所有 repo 共享(UI 配)|

---

## 不要做的事

- ❌ **本地跑 `yarn release`** —— 必须经 GitHub Actions workflow,避免 git/npm 不同步的脏状态(0.1.2 那次教训)
- ❌ **手 改 `CHANGELOG.md`** —— 由 release-it 维护,手改下次发版会被前置插入打乱
- ❌ **直接 push main** —— ruleset 拦着,无意义
- ❌ **`npm publish` 手动** —— 走 OIDC trusted publishing 后,本地没 npm 凭据
- ❌ **手 改自动生成的 `data.ts` / lockfile / 类型 declaration** —— 都是脚本 / 工具产物,手改下次重新生成会被覆盖
- ❌ **`release.yml` 加 `NPM_TOKEN` 回退** —— Trusted Publishing 是单一发版凭据,不要混杂方案
- ❌ **在 Dependabot PR 上手动 `git push --force`** —— 一旦你 push 过,Dependabot 视为你接管这个 PR,不再自动 rebase / recreate;且你本地 `yarn install` 解析可能跟 bot 不同,引入坏 yarn.lock。坏了就 `@dependabot close` 让 bot 重开
- ❌ **把 `pr_agent` 加进 ruleset 的 required status checks** —— AI review 是参考性,DeepSeek API 临时挂或 review 慢会卡死合并
- ❌ **无脑 `@dependabot ignore this major version`** —— 有些 major 实质是 `engines.node` bump 或内部重构,user-facing API 无变化(参考 release-it 19→20)。**先看 changelog 再决定 ignore**
- ❌ **删 `unif-design/.github` repo / 强制 push 它的 main** —— 所有 caller workflow 引用 `@main`,会同时挂掉所有 repo 的 PR Agent。要改重大版本走 PR / 用 git tag (`@v1`) 引用

---

[← 索引](../AUTOMATION.md) · [← 排查常见报错](./11-troubleshooting.md)
