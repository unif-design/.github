# unif-design / .github

`unif-design` 组织的**默认配置仓库** —— 集中维护 org 共享的 CI workflow、文档标准、PR/Issue 模板。

## 文件作用

| 文件 | 作用 | 共享机制 |
|---|---|---|
| `templates/` | 标准 workflow + 配置文件源(`ci.yml` 四仓最优并集 / release / lefthook / PR&Issue 模板 / SECURITY;native 仓另发 `native-lint.yml` / `nightly-build-check.yml` / `.clang-format`) | `scripts/sync-repo.sh` 下发到各 repo |
| `templates/AGENTS.md` | camera / design / hms-scan / umeng 四仓共享 Agent bootstrap 唯一真相源;完整标准在 `unif-design/skills` 的 `rn-library` Skill | `scripts/sync-agent-standards.sh` marker 级同步 |
| `scripts/sync-repo.sh` | 把 `templates/` 同步到目标 repo(变量替换 + 条件分发;四仓另同步共享 Agent bootstrap;不 commit / 不 push) | 见 [AUTOMATION docs/13](docs/13-sync.md) |
| `scripts/sync-agent-standards.sh` | 只刷新四仓根 `AGENTS.md` 的共享 bootstrap marker 区块,不改仓库特有规则(不 commit / 不 push) | 可独立运行,也由全量同步按仓名调用 |
| `scripts/setup-repo.sh` | 配 GitHub 端(merge / ruleset / security / Pages) | 见 [ONBOARDING](ONBOARDING.md) |
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

## 标准 workflow 模板 + 一键同步

`templates/` 是所有仓 workflow / 配置文件的**唯一标准源**,`templates/AGENTS.md` 是 `react-native-camera` / `react-native-design` / `react-native-hms-scan` / `react-native-umeng` 四仓共享 Agent bootstrap 唯一真相源;完整共享标准在 `unif-design/skills` 的 `rn-library` Skill。`scripts/sync-repo.sh <repo>` 一键下发(变量替换 + 条件分发;命中四仓时另同步共享 Agent bootstrap;不 commit / 不 push,改动留给各仓 review + PR)。

```sh
./scripts/sync-repo.sh react-native-design
```

`ci.yml` 取四仓最优并集(actionlint 加固 / `changes` 门控 / build-android temurin / build-ios macos-26+prebuilt)。覆盖策略:workflow 强制统一,`.pr_agent.toml` 等带 repo 特化的配置仅缺时创建;已停用的 Dependabot 配置和自动合并 workflow 会被主动移除。native 仓(有手写 `.kt/.mm`,即 umeng / hms-scan)按 `HAS_NATIVE_SRC` 条件多发 `native-lint.yml`(required check:`lint-cpp` / `lint-kotlin`)+ `nightly-build-check.yml`(advisory canary)+ `.clang-format`。详见 [docs/13-sync.md](docs/13-sync.md)。

上述四仓的根 `AGENTS.md` 例外:全量同步会调用 `scripts/sync-agent-standards.sh`,但它只替换 `BEGIN/END UNIF REACT NATIVE STANDARD` marker 之间的共享 bootstrap,不会整文件覆盖。四仓特有规则继续维护在各自根 `AGENTS.md` 的 marker 外;非四仓明确跳过此步骤。marker 脚本只更新 bootstrap,marker 外正文仍须语义审查。也可为四仓单独运行 `./scripts/sync-agent-standards.sh <repo-name> [target-repo-path]`。两个同步脚本都只修改目标工作树,不 commit / 不 push。历史 `docs/superpowers/specs/` 与 `docs/superpowers/plans/` 记录当时设计,不回写。

## 自动化流程标准

整套 CI / 发版 / 人工依赖升级 / Branch protection 标准 + 排查 SOP,见 [AUTOMATION.md](AUTOMATION.md)。

参考实例:[`unif-design/react-native-design`](https://github.com/unif-design/react-native-design)。

## 维护

- **Reusable workflow**:`.github/workflows/pr-agent.yml` 合入 `main` 后,对引用 `@main` 的 caller repo 立即生效,不需要逐仓 sync。
- **复制 / marker 模板**:`templates/` 合入 `main` 只更新标准源;必须逐仓运行 `scripts/sync-repo.sh`,或仅更新 Agent 标准时运行 `scripts/sync-agent-standards.sh`,再 review diff 并通过各仓 PR + CI 合入。

Reusable workflow 如果改用 `@v1` 这类 tag 引用,则由各 caller 自行升级。
