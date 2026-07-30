# React Native 库 Agent 共享标准设计

## 目标

为 `react-native-camera`、`react-native-design`、`react-native-hms-scan` 和
`react-native-umeng` 建立一份组织级 Agent 开发基线,并保留各仓自己的架构、命令和
领域约束。

共享标准必须让 Agent:

- 动手前读取当前会话可用的相关 Skill,并先检查 Git 分支与工作树。
- 不在 `main` 上开发或直接 push;从任务分支提交并通过 PR 合入。
- 理解 PR CI 与合并后自动发布的边界,不手工抢跑版本、tag 或 npm publish。
- 每次库改动都核对 website / llms.txt / 对应消费侧 Skill,而不只在 API 改名时检查。
- 将 Design 0.20.0、Gesture Handler 3 与 Carousel 5 的 peer metadata 冲突视为已验证
  的窄例外,不重复询问或把它当作 blocker。

## 方案

采用“中央模板 + 根 `AGENTS.md` 受控区块 + 仓库特有正文”。

- `.github/templates/AGENTS.md` 是共享区块的唯一真相源。
- `scripts/sync-agent-standards.sh` 只新增或替换带固定 marker 的共享区块。
- 各仓根 `AGENTS.md` 继续保存本仓定位、命令、架构、测试和特例。
- 各仓 `CLAUDE.md` 只保留 `@AGENTS.md`,避免两份正文漂移。
- `scripts/sync-repo.sh` 调用专用同步脚本,但仍保持“不 commit、不 push”的既有边界。

不使用独立 Agent Skill。共享规则是每次仓库开发都必须生效的 always-on 约束,依赖
Skill 自动触发会漏载;现有 `camera`、`design`、`hms-scan`、`umeng-share` Skill 继续只
负责消费者接入与排障。

## 区块结构与优先级

共享区块插入根 `AGENTS.md` 的 H1 后,使用以下 marker:

```text
<!-- BEGIN UNIF REACT NATIVE STANDARD -->
<!-- END UNIF REACT NATIVE STANDARD -->
```

区块内只保存四仓都成立的规则:

1. 任务开始时的 Skill 发现、Git 状态检查和分支门禁。
2. 实现、验证、PR、CI 与自动发布流程。
3. 仓库到消费侧 Skill 的精确映射及同步判据。
4. 已接受的 Carousel 5 / Gesture Handler 3 兼容例外。
5. 共享规则与仓库特有规则的冲突处理。

仓库特有正文可以补充或收紧共享标准。具体命令、平台实现和测试方式以仓库特有正文为
准;它不得放宽“不直推 main”“不得漏查 Skill”“不得全局忽略 peer dependency”等共享
门禁。发现真正矛盾时先报告冲突,不得自行静默选择。

## Git、CI 与发布契约

Agent 在修改前先执行只读状态检查:

1. 位于 `main` 时,先创建语义明确的任务分支。
2. 已位于与当前任务一致的非 `main` 分支时,保留该分支和既有改动,不额外套娃建分支。
3. 不覆盖、暂存或提交不属于当前任务的改动。
4. 完成验证后使用 conventional commit,推送任务分支并创建 PR。
5. PR 触发 CI;CI 未通过不得绕过。
6. PR 合入 `main` 后,命中 release workflow 路径的代码改动由自动化发布。除非任务明确
   是人工应急发布,否则 Agent 不手工改版本、打 tag 或运行 npm publish。

## Skill 与文档联动

共享区块按仓库名渲染对应 Skill:

| 仓库 | Skill |
| --- | --- |
| `react-native-camera` | `camera` |
| `react-native-design` | `design` |
| `react-native-hms-scan` | `hms-scan` |
| `react-native-umeng` | `umeng-share` |

每次库改动都检查公开 API、类型、运行时行为、错误语义、依赖 / 安装、原生配置、mock、
消费者示例、排障结论和文档入口。受影响时在同一交付同步 website、llms.txt 与对应
Skill;不受影响时也在交付说明核对范围和理由。Skills 仓不可访问或不可写时如实报告,
不得声称已经同步。

## 已接受兼容性例外

`@unif/react-native-design@0.20.0` 要求
`react-native-gesture-handler >=3 <4`,而
`react-native-reanimated-carousel@5.0.0` 的发布 metadata 要求
`react-native-gesture-handler >=2.9 <3`。范围没有交集,但当前 RNGH 3 + Carousel 5
组合已完成项目适配和验证。

因此 Agent:

- 不能只凭该 peer warning 再次询问用户、阻塞任务或建议降级任一方。
- 保留仓库已有的 scoped override / 窄 allowlist 和严格漂移检查。
- 不使用全局 override、`--force` 或 `--legacy-peer-deps` 掩盖其他 peer 问题。
- 只在出现可复现的相关构建 / 运行回归,或 Carousel 版本、peer range、RNGH major
  发生变化时重新评估。

## 同步脚本契约

`scripts/sync-agent-standards.sh <repo-name> [target-path]`:

- 仅接受四个显式支持的仓库名。
- 从目标 `package.json` 校验仓库身份,并把当前仓库与 Skill 名渲染到共享区块。
- 目标首次接入时在 H1 后插入区块;已接入时原位替换。
- marker 缺一、重复或顺序错误时失败,不猜测修复。
- 除共享区块外保持目标 `AGENTS.md` 内容不变。
- 重复运行结果完全一致。
- 不执行 `git add`、commit、push 或 PR。

## 验证

- Shell 测试覆盖首次插入、原位更新、幂等、仓库映射、本地正文保留和坏 marker 拒绝。
- `bash -n` 与 ShellCheck 校验脚本。
- 在四仓工作树执行 agents-only 同步并逐仓 review diff。
- 确认四仓 `CLAUDE.md` 精确为一行 `@AGENTS.md`。
- 对共享提示词做前向场景验证,重点检查分支门禁、Skill 联动和已接受依赖例外。
- 最终执行 `git diff --check` 及各仓已有的 Agent 指令验证。

## 非目标

- 不把库源码开发标准加入 `portal` 或消费侧包 Skill。
- 不通过本任务自动合并目标仓 PR。
- 不顺带统一四仓所有 workflow、依赖或业务实现。
- 不用共享模板覆盖仓库特有开发说明。
