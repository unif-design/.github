<!-- BEGIN UNIF REACT NATIVE STANDARD -->

## 组织共享开发流程

你维护的仓库是 `{{REPO}}`。本区块定义共享门禁;仓库正文只保存本仓特有规则,且只能补充或收紧共享规则。真实冲突必须如实报告,不得静默选择任一规则。

## 任务开始: Skill 发现 + Git 状态 + 分支

- 先查找适用的 Skill 并阅读其说明,再执行任务。
- 开始前运行 `git status --short --branch`,确认工作区和分支状态。
- 若当前位于 `main`,必须在任何修改前创建并切换到语义明确的任务分支;若已位于与任务匹配的非 `main` 分支,继续在该分支工作并保留既有改动。
- 不得混入、覆盖、暂存或提交无关改动。
- `main` 是合并门禁分支: 禁止直接推送 `main`,所有改动必须经 PR 和 CI 进入 `main`。

## 实现与交付: 验证 + PR CI + 合并后自动发布

- 实现后运行仓库特有验证,并使用 conventional commit 提交。
- 推送任务分支并创建 PR;PR CI 通过后再合入 `main`。
- 命中 release workflow 路径的改动会在合入后自动发布。除任务明确要求人工应急发布外,不得手工改版本、创建 tag 或执行 `npm publish`。

## website / llms.txt / {{SKILL}} Skill 联动

- 每次库改动都必须核对 `website`、`llms.txt` 和 `../skills/skills/{{SKILL}}/` 中对应的 `{{SKILL}}` Skill。
- 明确核对公共 API、类型、运行时行为、错误语义、依赖 / 安装、原生配置、mock、消费者示例、排障结论和文档入口。
- 受影响项与本次交付同步更新;不受影响时说明核对范围与理由;不可访问或不可写时如实报告。

## RNGH 3 / Carousel 5 条件化窄例外

- 仅当仓库实际采用 `@unif/react-native-design@0.20.0`、`react-native-gesture-handler >=3 <4` 和 `react-native-reanimated-carousel@5.0.0` 时适用;该规则不要求未采用此组合的仓库升级依赖。
- Carousel 发布 metadata 的 RNGH 范围为 `>=2.9 <3`,与 Design 的 RNGH 范围无交集,但当前组合已适配并验证。
- 不得仅凭 warning 再次询问、阻塞或建议降级;保留 scoped override、窄 allowlist 和严格漂移检查,禁止全局 override、`--force`、`--legacy-peer-deps`。
- 仅在可复现相关回归,或 Carousel 版本 / peer range / RNGH major 变化时重评。

## 共享与本仓规则边界

本区块外的内容属于本仓规则,同步时必须保留。模板已有的通用规则不得在仓库正文重复。

<!-- END UNIF REACT NATIVE STANDARD -->
