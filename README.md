# unif-design / .github

`unif-design` 组织的**默认配置仓库** —— 集中维护 org 共享的 CI workflow、文档标准、PR/Issue 模板。

## 文件作用

| 文件 | 作用 | 共享机制 |
|---|---|---|
| `.github/workflows/pr-agent.yml` | PR Agent + DeepSeek 自动 review,reusable workflow | 各 repo 写 5 行 caller 调用 |
| `.github/PULL_REQUEST_TEMPLATE.md` | 全 org 默认 PR 模板(通用版)| repo 自己有同名文件则 override |
| `CONTRIBUTING.md` | 全 org 通用贡献指南 | 同上 |
| `AUTOMATION.md` | 自动化流程标准(CI / 发版 / 依赖 / branch protection)| 各 repo 用链接引用 |

## Reusable workflow 调用

任何 unif-design 下的 repo 接入 PR Agent + DeepSeek 自动 review:

```yaml
# 在你的 repo 加 .github/workflows/pr-agent.yml
name: PR Agent

on:
  pull_request:
    types: [opened, reopened, synchronize, ready_for_review]
  issue_comment:
    types: [created]

permissions:
  contents: read
  pull-requests: write
  issues: write

jobs:
  call:
    uses: unif-design/.github/.github/workflows/pr-agent.yml@main
    secrets:
      DEEPSEEK_API_KEY: ${{ secrets.DEEPSEEK_API_KEY }}
```

在自己的 repo 根目录可选加 `.pr_agent.toml` 补项目特有的 review prompt(覆盖 org 通用 prompt)。

## 自动化流程标准

整套 CI / 发版 / Dependabot / Branch protection 标准 + 排查 SOP,见 [AUTOMATION.md](AUTOMATION.md)。

参考实例:[`unif-design/react-native-design`](https://github.com/unif-design/react-native-design)。

## 维护

修改任意 yml / md → push 到 main → **立刻**对所有 caller repo 生效(reusable workflow 引用 `@main`)。

如果担心改动影响,改用 `@v1` 这种 tag 引用,各 caller 自行升级。
