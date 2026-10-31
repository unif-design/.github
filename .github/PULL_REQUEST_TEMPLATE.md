## 变更概述

<!-- 1-2 句:做了什么 / 为什么。链接 issue 用 `Closes #N`。 -->

## 类型

<!-- conventional-commits 类型,跟 commit msg 前缀对齐。多选用 - [x] -->

- [ ] `feat` 新功能(触发 minor 发版)
- [ ] `fix` Bug 修复(触发 patch 发版)
- [ ] `refactor` / `chore` / `docs` / `test` / `ci`（是否发版按本仓工作流与版本规则判断）
- [ ] **包含 BREAKING CHANGE**（主版本升级需明确授权，并在 commit body 写 `BREAKING CHANGE: ...`）

## 验证

- [ ] `yarn lint`
- [ ] `yarn typecheck`(若仓库用 TypeScript)
- [ ] `yarn test`
- [ ] (若改了 UI 组件)亮 + 暗主题都看了

## 影响范围 / 注意点

<!-- 用了哪些 token / 哪些组件受影响 / 是否需要消费者同步改动 -->
