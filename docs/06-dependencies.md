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

### Auto-merge SOP(可选,推荐)

各 repo 加一个 ~30 行的 workflow,让符合条件的 Dependabot PR 自动启用 GitHub auto-merge,跑通 CI 后自动 squash merge,不用每周手动点。

跟上面的 **PR 处理 SOP** 是互补关系:SOP 描述**手动场景**(人审 changelog → 点 merge),本节描述**自动化场景**(符合条件的 patch / minor 自动合);major 仍然走 SOP 人审流程。

#### 工作流文件

`<repo>/.github/workflows/dependabot-auto-merge.yml`:

```yaml
name: Dependabot Auto-Merge

on:
  pull_request_target:
    types: [opened, reopened, synchronize]

permissions:
  pull-requests: write
  contents: write

jobs:
  automerge:
    if: github.actor == 'dependabot[bot]'
    runs-on: ubuntu-latest
    steps:
      - uses: dependabot/fetch-metadata@v2
        id: meta
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
      - name: Enable auto-merge for patch / minor
        if: |
          steps.meta.outputs.update-type == 'version-update:semver-patch' ||
          steps.meta.outputs.update-type == 'version-update:semver-minor'
        env:
          PR_URL: ${{ github.event.pull_request.html_url }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh pr merge --auto --squash "$PR_URL"
```

#### 关键决策

| 维度 | 选择 | 原因 |
|---|---|---|
| **Auto-merge 哪些类型** | **patch + minor** | major 由 [升级风险分级](#升级风险分级) 决定,case-by-case 人审 |
| **触发器** | `pull_request_target` 而非 `pull_request` | dependabot 在 `pull_request` 触发的 workflow 默认 GITHUB_TOKEN 是 read-only,改 `pull_request_target` 跑在 base branch 有 write 权限,不需要额外 Settings |
| **Security**(`pull_request_target` 危险吗?)| 安全 | dependabot 不是 fork(internal bot),且 workflow 不 checkout PR head 代码,只读 PR URL —— 无 supply chain 风险 |
| **跟 ruleset 交互** | 互补 | workflow **启用** GitHub auto-merge,GitHub 自己等满足 branch protection ruleset(必须 PR + 5 个 CI check + squash only)才合;ruleset 是 gate |
| **位置** | 单 repo 各自一份 | ~30 行,reusable workflow 收益低,各 repo 复制 yml 即可 |

#### 实际行为

```
Dependabot 周一开 PR(patch 升级)
   ↓
workflow 自动跑(pull_request_target opened)
   ↓
fetch-metadata 拿升级类型 → patch
   ↓
gh pr merge --auto --squash → GitHub auto-merge enabled
   ↓
GitHub 等 CI 5 个 check 全绿 + 其他 ruleset 满足
   ↓
全部满足 → GitHub 自动 squash merge
   ↓
PR 合到 main,源 branch 自动删
```

对应的 major PR 流程不变:不触发 auto-merge → 人工 review changelog(走上面 **PR 处理 SOP**)→ 决定合 / close / ignore。

#### 接入新 repo

> ⚠️ **前置:repo Settings → General → Pull Requests → "Allow auto-merge" 必须勾上**(不勾 `gh pr merge --auto` 静默失败)。`scripts/setup-repo.sh` 自动开这个开关,新 repo 接入不用手配;手配走旧 repo 自己去 repo Settings 勾。

复制 `<reference-repo>/.github/workflows/dependabot-auto-merge.yml` 到新 repo 同位置即可。不需要新 secret(用默认 `GITHUB_TOKEN`)。

```sh
# 单 repo 接入(在新 repo 根目录)
mkdir -p .github/workflows
cp /path/to/reference-repo/.github/workflows/dependabot-auto-merge.yml \
   .github/workflows/dependabot-auto-merge.yml
git add .github/workflows/dependabot-auto-merge.yml
git commit -m "ci: 加 dependabot auto-merge workflow"
```

#### 什么时候**不**该用

- 你想每个依赖升级都手审(强合规项目 / 自托管 critical service)
- 你的 CI 不够覆盖(没 type / integration test 等),怕 patch 升级偷偷引入 BC
- 团队规模小到不在乎每周点几下手动 merge

### 何时关 + ignore

| 情形 | 操作 |
|---|---|
| PR yarn.lock 坏了 / 解析错误 | `@dependabot recreate` 重新生成;再不行 `@dependabot close` 等下周再试 |
| major 跨版本有 breaking | `@dependabot close` + 评论 `@dependabot ignore this major version` |
| yarn 4 跟某个包暂时不兼容 | 手动 close,本地手动升级调试 |

---


---

[← 索引](../AUTOMATION.md) · [← Branch protection (Rulesets)](./05-branch-protection.md) · [安全扫描 →](./07-security.md)
