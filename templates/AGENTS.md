<!-- BEGIN UNIF REACT NATIVE STANDARD -->

## 组织共享开发流程

你维护的仓库是 `{{REPO}}`。开始任务前先发现可用 Skill,检查 Git 状态和当前分支,确认改动范围后再实现。

## 任务开始: Skill 发现 + Git 状态 + 分支

- 先查找适用的 Skill 并阅读其说明,再执行任务。
- 开始前运行 `git status --short --branch`,确认工作区和分支状态。
- 在与任务匹配的分支上工作,不要混入无关改动。

## 实现与交付: 验证 + PR CI + 合并后自动发布

- 实现后运行与改动相称的验证,提交 PR 前确认 CI 配置可用。
- PR CI 通过后再合并;合并到发布分支后由仓库的自动发布流程处理发布。

## website / llms.txt / {{SKILL}} Skill 联动

- 查 API 和组件用法时,优先阅读 `website` / `llms.txt`。
- 需要本仓库能力约束时,阅读 `../skills/skills/{{SKILL}}/` 中的 `{{SKILL}}` Skill。

## RNGH 3 / Carousel 5 已接受窄例外

仅在既有兼容性边界内保留 RNGH 3 / Carousel 5;不要将该例外扩展到新的依赖或模块。

## 共享与本仓规则边界

本区块定义四个仓库共用的开发标准。本区块外的内容属于本仓规则,同步时必须保留;若两者冲突,以更具体且不违背共享标准的本仓规则为准。

<!-- END UNIF REACT NATIVE STANDARD -->
