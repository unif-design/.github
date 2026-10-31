# Unif 组织默认文件

本仓提供组织默认的贡献指南、安全政策、行为准则和 PR 模板。工程交付标准已迁出；消费仓保存实际采用的工作流、检查工具及配置，CI 不再读取本仓的共享工作流或下载标准脚本。

## 当前维护入口

| 内容 | 唯一维护来源 |
|---|---|
| GitHub CI、模板同步、仓库保护与发布机制 | [Uni Skills 的 github-delivery](https://github.com/unif-skill/uni-skills/tree/main/skills/github-delivery) |
| Unif RN 组织约定与非敏感接入配置 | [Unif Dev 的 code-delivery](https://github.com/unif-skill/unif-portal-dev-skills/tree/main/skills/code-delivery) |
| 工程实际执行版本、专属命令及验证 | 对应仓库的 `.github/delivery.json`、工作流与开发资料 |

两套技能独立安装和使用。组织配置在接入时写入目标工程；通用工具不查找其他技能的安装目录。标准更新通过同步、审查和工程 PR 生效，已接入工程的 CI 不依赖技能安装。

## 历史资料

`AUTOMATION.md`、`ONBOARDING.md` 和 `docs/` 保留迁移前的设计、操作说明与验收依据，不再作为新工程接入入口。已迁移的旧脚本、模板及共享工作流从当前分支移除；完整旧实现可在[迁移前修订](https://github.com/unif-design/.github/tree/ad4091aa2c508b2a98076455a89897fd65dd2b85)追溯。
