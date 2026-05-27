# Contributing to Unif Design projects

`unif-design` 组织下所有仓库的通用贡献指南。各仓库可以在自己的 `CONTRIBUTING.md` 里 override / 扩展项目特有的内容。

## 工作流

main 受 branch protection 保护,不能直接 push。所有改动走 **feature branch + PR**:

```sh
git switch -c <type>/<short-description>
# 例:feat/login-flow / fix/icon-fallback / chore/upgrade-deps
```

提交前本地验证:

```sh
yarn lint
yarn typecheck       # 若用 TypeScript
yarn test
```

push 到远端 + 在 GitHub UI 开 PR。PR template 会自动套上。

## Conventional Commits

commit message 必须符合 [Conventional Commits](https://www.conventionalcommits.org/) 规范,由 `commitlint` 强校验。常用前缀:

| 前缀 | 用途 | 自动发版行为(若仓库配了)|
|---|---|---|
| `feat` | 新功能 | bump **minor** |
| `fix` | Bug 修复 | bump **patch** |
| `refactor` / `chore` / `docs` / `test` / `style` / `perf` / `ci` | 维护类 | **不发版** |
| body 含 `BREAKING CHANGE:` | 破坏性变更 | bump **major** |

约束:

- subject 全小写,不含大写英文专有名词(commitlint `subject-case` 规则)
- subject 不要句号结尾
- 一次 commit 一个 logical change

## PR 流程

1. CI 必须全绿才能合(由 branch protection 强制)
2. self-review diff,确认没有遗留 console.log / 调试代码
3. 关注 PR Agent(DeepSeek 自动 review)的评论,采纳有价值的建议
4. 点 **Squash and merge** —— PR 上多个 commit 会合成 1 个进 main(跟 conventional commits 完美对齐)
5. 源 branch merge 后自动删

## 共享基础设施

org 级别集中管理的:

- **Secret `DEEPSEEK_API_KEY`** —— 全 org 共享,PR Agent 用
- **Reusable workflow `unif-design/.github/.github/workflows/pr-agent.yml`** —— PR-Agent + DeepSeek 自动 review,各 repo 5 行 caller 调用
- **PR template** —— 默认套用(各 repo 可 override)

## 项目特有内容

具体仓库的:开发环境 setup、scripts、原生构建、发版流程,看各 repo 自己的 `CONTRIBUTING.md` 或 `docs/` 目录。
