<!-- BEGIN UNIF REACT NATIVE STANDARD -->

## 组织共享开发流程

你维护的仓库是 `{{REPO}}`。开始任务前先发现可用 Skill,检查 Git 状态和当前分支,确认改动范围后再实现。

## 任务开始: Skill 发现 + Git 状态 + 分支

- 先查找适用的 Skill 并阅读其说明,再执行任务。
- 开始前运行 `git status --short --branch`,确认工作区和分支状态。
- 必须在与任务匹配的现有分支上继续工作;保留该分支,不要无故新建、切换或删除它。
- `main` 是合并门禁分支: 禁止直接推送 `main`,所有改动必须经 PR 和 CI 进入 `main`。

## 实现与交付: 验证 + PR CI + 合并后自动发布

- 实现后运行与改动相称的验证,提交 PR 前确认 CI 配置可用。
- PR CI 通过后再合入 `main`;只有 PR 合入 `main` 触发自动发布,不得绕过此边界。
- 禁止手工修改版本、创建 tag 或执行 `npm publish`;发布交给合入后的自动流程。

## website / llms.txt / {{SKILL}} Skill 联动

- 查 API 和组件用法时,优先阅读 `website` / `llms.txt`。
- 需要本仓库能力约束时,阅读 `../skills/skills/{{SKILL}}/` 中的 `{{SKILL}}` Skill。
- 每次库改动都必须核对 website / llms.txt / 消费侧 Skill 的全影响面。受影响项与本次交付同步更新;确认不受影响时说明理由;不可访问或不可写时如实报告。

## RNGH 3 / Carousel 5 已接受窄例外

- 已接受的例外是 Design `0.20.0`、RNGH `>=3<4`、Carousel 5 metadata `>=2.9<3`。
- 不得再次询问、阻塞或建议降级;保留 scoped override / 窄 allowlist,禁止全局 override、`--force`、`--legacy-peer-deps`。
- 仅在可复现的相关回归,或 Carousel 版本 / peer range / RNGH major 变化时重评此例外。

## 共享与本仓规则边界

本区块定义四个仓库共用的开发标准。本区块外的内容属于本仓规则,同步时必须保留。本仓规则只能补充或收紧,不得放宽共享门禁;出现真实冲突时必须如实报告,不得静默选择任一规则。

<!-- END UNIF REACT NATIVE STANDARD -->
