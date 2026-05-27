[← 索引](../AUTOMATION.md) · [← Branch protection (Rulesets)](./05-branch-protection.md) · [安全扫描 →](./07-security.md)

---

# 依赖管理(Dependabot)

### 配置(`.github/dependabot.yaml`)

```yaml
version: 2
updates:
  - package-ecosystem: npm
    directory: /
    schedule: { interval: weekly, day: monday, time: '09:00', timezone: Asia/Shanghai }
    open-pull-requests-limit: 5
    labels: [dependencies]
    commit-message: { prefix: chore, include: scope }
    groups:
      types: { patterns: ['@types/*'] }
      react-native: { patterns: ['react-native', 'react-native-*', '@react-native/*', '@react-native-community/*'] }
      eslint: { patterns: ['eslint', 'eslint-*', '@eslint/*', '@eslint-*'] }
      jest: { patterns: ['jest', 'jest-*', '@jest/*'] }
      commitlint: { patterns: ['commitlint', '@commitlint/*'] }
      release-it: { patterns: ['release-it', '@release-it/*'] }

  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: monthly }
    labels: [dependencies, github-actions]
    commit-message: { prefix: ci }
```

每周一 09:00(北京时间)Dependabot 扫描 npm 依赖,按 group 打包 PR。GitHub Actions 月更。

### PR 处理 SOP

```
1. 看 PR 描述里 Dependabot 自动贴的 changelog
2. CI 必须 5 个绿(ruleset 拦着)
3. 决策:
   ├─ patch / 同 minor → 直接合
   ├─ minor 跨版本   → 看 changelog,大概率合
   ├─ major 跨版本   → 必看 changelog!engines bump / 内部重构 → 合;API breaking → 关 + ignore
   └─ 不想要这个版本 → 评论 ignore 命令
4. 点 Squash and merge
```

### `@dependabot` 命令清单

| 命令 | 作用 |
|---|---|
| `@dependabot rebase` | 把 PR rebase 到 main 最新 HEAD,**只更新 lock,不重新生成 PR** |
| `@dependabot recreate` | 丢弃整个 PR branch,基于 main 完全重新生成 PR(用于修复 lockfile 错乱)|
| `@dependabot merge` | CI 绿后自动合 |
| `@dependabot squash and merge` | 同上,但 squash merge |
| `@dependabot close` | 关闭 PR + 删 branch |
| `@dependabot ignore this version` | 忽略当前版本(下个 patch / minor 会再开 PR)|
| `@dependabot ignore this minor version` | 忽略整个 minor series(直到下个 minor)|
| `@dependabot ignore this major version` | 忽略整个 major series(强烈建议某些 major 用)|
| `@dependabot ignore this dependency` | 完全停掉这个依赖的 PR(只在确定不再升级时用)|

#### rebase vs recreate 的关键区别

| 命令 | 行为 | 用在 |
|---|---|---|
| `@dependabot rebase` | 把 PR rebase 到 main 最新 HEAD,**保留** lockfile 现有 resolution 状态,只解决 git 层面冲突 | PR 落后 main 但 lockfile 本身没坏 |
| `@dependabot recreate` | **完全丢弃** 当前 branch,基于 main 重跑依赖解析,重新生成 lockfile | lockfile 错乱 / 解析到错误版本 / 你自己 force-pushed 过 |

**关键陷阱**:`rebase` 不会重新跑 `yarn install`,所以**坏的 yarn.lock 不会被修复**。如果 PR 报怪异错误(比如 `scopeManager.addGlobals is not a function` 这种依赖版本不匹配),用 `recreate`,**不要**用 `rebase`。

### 升级风险分级

| 类型 | 自动合 | 备注 |
|---|---|---|
| `@types/*` patch | ✅ 直接合 | 只影响类型,运行时无影响 |
| 单 dev lib patch(turbo / prettier / lefthook)| ✅ 直接合 | dev 工具,不影响 npm 包产物 |
| RN minor / patch | ⚠️ CI 全绿才合 | 看 example build 是否成功 |
| **major 跨版本** | ⚠️ 必看 changelog | 区分 "engines bump 无害" vs "API breaking",见下方 |
| **`react-native` 自身 major** | ❌ 不走 Dependabot | 手动 feature branch 升,本地完整测试 |
| **`peerDependencies` 收紧** | ❌ 不走 Dependabot | 影响消费者,要专门发版通告 |

#### major 升级 case-by-case 判断(不要无脑 ignore)

不是所有 major 都意味着 breaking。**真去看 changelog**,按这个判断:

| changelog 显示 | 实际危险度 | 处理 |
|---|---|---|
| **只 bump `engines.node` 最低版本**(去掉旧 Node 支持)| 0(只要你 Node 版本满足新 requirement)| 直接合,本质是"维护层"升级 |
| **内部依赖替换 / 重构,API 不变** | 0 | 直接合 |
| **API 重命名 / 改签名** | 高 | 看你用到的 API 是否在变化清单,在 → 必须改代码;不在 → 合 |
| **默认配置变了**(打破现有行为)| 中-高 | 仔细测,可能需要显式设回旧默认 |
| **完全重写架构 / 多个 API 不兼容** | 极高 | `@dependabot close` + `@dependabot ignore this major version`,等社区稳一两个 minor 再升 |

**反例**:`release-it 19 → 20` 标 major,实际只是 `engines.node` 提高最低版本,user-facing API 完全不变。无脑 ignore 会错过这种无害升级。

**正例**:某 API 重写的 major(`eslint 8 → 9` 等),pluginAPI 完全不同,需要等 plugin 生态跟上才能升。

### 何时关 + ignore

| 情形 | 操作 |
|---|---|
| PR yarn.lock 坏了 / 解析错误 | `@dependabot recreate` 重新生成;再不行 `@dependabot close` 等下周再试 |
| major 跨版本有 breaking | `@dependabot close` + 评论 `@dependabot ignore this major version` |
| yarn 4 跟某个包暂时不兼容 | 手动 close,本地手动升级调试 |

---


---

[← 索引](../AUTOMATION.md) · [← Branch protection (Rulesets)](./05-branch-protection.md) · [安全扫描 →](./07-security.md)
