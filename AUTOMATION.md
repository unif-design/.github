# Unif Design 自动化流程标准

`unif-design` 组织所有仓库共享的 CI / 发版 / 依赖管理 / PR review 标准。**以 `@unif/react-native-design` 仓库为参考实例**,其他 repo 套用同一套模式(配置文件路径、命令、ruleset 勾选项一致;只有 npm 包名 / specific scripts 名等需要替换)。

各 repo 在自己的 README / CONTRIBUTING 里加链接 `https://github.com/unif-design/.github/blob/main/AUTOMATION.md` 指过来即可,**不需要每个 repo 复制一份**。

---

## 总览

```
开 feature branch
       │
       │ 改代码 + 本地 verify
       ▼
   git commit (conventional commits)
       │
       │ git push -u origin <branch>
       ▼
   GitHub UI 开 PR(PR template 自动套)
       │
       │ CI 自动跑 5 个 check
       ▼
   ┌─────────────────┐
   │ Branch protection│  阻止直接 push main
   │   - PR 必须     │  阻止合并未通过 CI
   │   - CI 必须绿   │
   └────────┬────────┘
            │ Squash and merge
            ▼
          main
            │
            │ 命中 release.yml paths?
            ▼
   ┌─────────────────────────────────┐
   │ Release workflow(自动 / 手动)  │
   │   1. 跑 lint + typecheck + test │
   │   2. release-it --ci            │
   │      └ 推断 bump 类型           │
   │      └ npm Trusted Publishing   │
   │      └ git commit + tag         │
   │      └ 创建 GitHub Release      │
   │      └ 写 CHANGELOG.md          │
   └─────────────────────────────────┘
            │
            ▼
       npm registry + GitHub Release
```

---

## 日常开发主流程

### 1. 开 feature branch

main 受 branch protection 保护,**禁止直接 push**。所有改动必须走 feature branch + PR。

```sh
git switch -c <type>/<short-description>
# 例:
#   feat/camera-shutter-button
#   fix/icon-warning-fallback
#   chore/upgrade-eslint
#   docs/readme-installation
```

branch 命名建议跟 conventional commits 的 `type` 对齐,见名知意。

### 2. 改代码 + 本地 verify

```sh
yarn lint
yarn typecheck
yarn test
# 若改 RN 组件:
yarn example start && yarn example ios   # 或 android,跑一遍 example 应用
```

本地必须**先过这 3 项**,再 commit。CI 跑的就是这 3 项 + 原生 build,本地挂的 CI 必挂。

### 3. commit(Conventional Commits)

```sh
git commit -m "<type>(<scope>): <subject>"
```

| `type` | 含义 | 触发版本发布 |
|---|---|---|
| `feat` | 新功能 | **minor**(0.1.x → 0.2.0)|
| `fix` | Bug 修复 | **patch**(0.1.2 → 0.1.3)|
| `BREAKING CHANGE:` 在 body | 破坏性变更 | **major**(0.x → 1.0.0)|
| `refactor` / `chore` / `docs` / `test` / `ci` / `style` / `perf` | 维护类 | **不发版** |

约束(由 `commitlint` + lefthook commit-msg hook 本地强校验):

- subject 全小写,**不能含大写英文专有名词**(`commitlint config-conventional` 默认规则)
  - ❌ `feat(components): Empty 加 icon prop`
  - ✅ `feat(components): empty 加 icon prop`(组件名小写)
- subject 不要句号结尾
- 一次 commit 一个 logical change

详见 `.commitlintrc` / `package.json#commitlint` 与 `lefthook.yml`。

### 4. push feature branch

```sh
git push -u origin <branch>
```

feature branch **不受 ruleset 限制**,任意 push、任意 force-push。

### 5. 开 PR

GitHub repo 主页会自动弹 banner `Compare & pull request`,点开。

PR template(`.github/PULL_REQUEST_TEMPLATE.md`)自动套上,填:
- 变更概述(1-2 句)
- 类型(勾对应的 `feat` / `fix` / `chore` 等)
- 验证清单
- 影响范围

### 6. CI 5 个 check 必须全绿

| Check | 跑什么 | 阻塞合并 |
|---|---|---|
| `CI / lint` | `yarn lint`(eslint + prettier)| ✅ |
| `CI / test` | `yarn test --maxWorkers=2 --coverage` | ✅ |
| `CI / build-library` | `yarn prepare`(bob build → `lib/`)| ✅ |
| `CI / build-android` | turbo 跑 example android 编译 | ✅ |
| `CI / build-ios` | turbo 跑 example iOS 编译(macos-latest)| ✅ |

ruleset 配了 5 个 check 为 required,缺一不可。

### 7. self-review + Squash and merge

PR 页面 → Files changed 看完整 diff → 满意 → 点 **Squash and merge** 按钮。

- 默认 commit msg = PR 标题(就是 conventional commits 格式)
- 必要时改下 commit body
- Confirm → branch 自动删(repo 已开 auto-delete head branches)

### 8. 合并后自动发版(若触发)

合并后:
- 如果改动**命中**`release.yml` paths(`src/** / scripts/** / package.json / yarn.lock`)→ Release workflow 自动跑
- 如果改动**不命中**(只改 docs / example / .github)→ 不触发 Release

详见 [发版机制](#发版机制release-workflow)。

---

## CI workflow(`.github/workflows/ci.yml`)

### 触发

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  merge_group:
    types: [checks_requested]
```

任何 PR + main push 都跑;合并队列(若启用)也跑。

### 并发取消

`concurrency.cancel-in-progress: true` —— 同一 ref 的旧 run 被新 push 取消,省 CI 时间。

### 5 个 job

- **`lint`** —— `yarn lint && yarn typecheck`,ubuntu-latest
- **`test`** —— `yarn test --maxWorkers=2 --coverage`,ubuntu-latest
- **`build-library`** —— `yarn prepare`(bob build),ubuntu-latest
- **`build-android`** —— turbo `build:android`,ubuntu-latest,带 turbo cache + gradle cache
- **`build-ios`** —— turbo `build:ios`,**macos-latest**(必须用 macOS runner),带 turbo cache + Pods

### 缓存策略

- `node_modules` + `.yarn/install-state.gz` —— 缓存 key 含 `yarn.lock` + `package.json`
- turbo 缓存 —— Android / iOS 各一份,key 含 `yarn.lock`
- Gradle wrapper / caches —— Android job 单独
- 缓存命中时跳过 JDK 装、跳过 Xcode 装、跳过 pod install

详见 `.github/actions/setup/action.yml`(composite action)。

---

## 发版机制(Release workflow)

### 触发(`release.yml`)

```yaml
on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'scripts/**'
      - 'package.json'
      - 'yarn.lock'
  workflow_dispatch:
    inputs:
      increment:
        description: '强制版本类型(留空走 conventional commits 自动推断)'
        type: choice
        options: ['', patch, minor, major]
```

两条路径:

1. **自动**:PR 合并到 main + 改动命中上述 paths → 工作流跑
2. **手动应急**:Actions → Release → Run workflow → 选 increment(`patch` / `minor` / `major` 或留空)

### 版本推断逻辑

`release-it` + `@release-it/conventional-changelog` plugin 扫描自上次 tag 以来的所有 commits:

```
有 BREAKING CHANGE  → bump major
有 feat:            → bump minor
有 fix:             → bump patch
只有 chore: / docs: / 等   → 不发版,release-it exit 0
```

`workflow_dispatch` 时若传了 `increment`,**强制**使用,跳过自动推断。

### Trusted Publishing(OIDC,无 token)

| 配置点 | 值 / 位置 |
|---|---|
| workflow permissions | `contents: write` + `id-token: write` |
| npm 端 trusted publisher | npmjs.com → 包 Settings → Publishing access → Trusted Publishers,绑定 `unif-design/react-native-design` 的 `release.yml` |
| **不要**配 NPM_TOKEN secret | 走 OIDC 完全没有 long-lived token |
| `package.json#release-it.npm.skipChecks: true` | **必须** —— 跳过 `npm whoami` 预检查(OIDC 没持久登录)|
| `npm install -g npm@latest` step | **必须** —— OIDC 要求 npm CLI ≥ 11.5.1 |

### 工作流 step 顺序

1. Checkout(fetch-depth: 0 → release-it 算 changelog 要全历史)
2. `./.github/actions/setup` —— Node + yarn install + cache
3. **Upgrade npm CLI** —— `npm install -g npm@latest`
4. Verify —— `yarn lint && yarn typecheck && yarn test`(发版 gate)
5. Configure git —— git user 设为 `github-actions[bot]`
6. **Release** —— `npx release-it [increment] --ci`
   - bump `package.json` version
   - 生成 changelog,写入 `CHANGELOG.md`(根据 `@release-it/conventional-changelog.infile`),前置追加新版本段
   - git commit `chore: release X.Y.Z`(含 package.json + CHANGELOG.md)
   - git tag `vX.Y.Z`
   - `npm publish`(走 OIDC trusted publishing)
   - git push commit + tag(走 GITHUB_TOKEN)
   - 创建 GitHub Release(走 GITHUB_TOKEN)

### `release-it` 配置(`package.json#release-it`)

```jsonc
{
  "git": {
    "commitMessage": "chore: release ${version}",
    "tagName": "v${version}"
  },
  "npm": {
    "publish": true,
    "skipChecks": true     // Trusted Publishing 必备
  },
  "github": {
    "release": true        // 自动创建 GH Release
  },
  "plugins": {
    "@release-it/conventional-changelog": {
      "preset": { "name": "angular" },
      "infile": "CHANGELOG.md"   // 写入仓库根 CHANGELOG.md
    }
  }
}
```

---

## Branch protection(Rulesets)

### 配置位置

`Settings → Rules → Rulesets → New branch ruleset`

### 关键配置

| 字段 | 值 |
|---|---|
| Ruleset Name | `protect main`(任意)|
| Enforcement status | **Active** |
| Bypass list | 留空(GitHub Actions bot 默认放行,直接试,不行再加 `Repository role: Admin` / `Maintain`)|
| Target branches | **Include default branch**(自动跟随 main)|

### Rules 勾选(只这 4 个)

- ✅ **Restrict deletions** —— 防 main 被删
- ✅ **Require a pull request before merging**(子选项:approvals = 0,单人项目 self-approve 会被堵)
- ✅ **Require status checks to pass**:
  - ✅ Require branches to be up to date
  - Required checks 加这 5 个:`lint`、`test`、`build-library`、`build-android`、`build-ios`
- ✅ **Block force pushes**

**不勾**:
- ❌ Require approvals(单人项目堵死自己)
- ❌ Restrict creations / updates(会拦 release-it bot)
- ❌ Require signed commits(没配 GPG)
- ❌ Require linear history / merge queue / signed commits(用不上)

### 副作用

- 直接 `git push origin main` → `GH013: Repository rule violations` 拒绝
- 必须经 PR + Squash merge
- release-it bot 用 `GITHUB_TOKEN` push 仍能过(GitHub Actions 默认放行)

---

## 依赖管理(Dependabot)

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

### 升级风险分级

| 类型 | 自动合 | 备注 |
|---|---|---|
| `@types/*` patch | ✅ 直接合 | 只影响类型,运行时无影响 |
| 单 dev lib patch(turbo / prettier / lefthook)| ✅ 直接合 | dev 工具,不影响 npm 包产物 |
| RN minor / patch | ⚠️ CI 全绿才合 | 看 example build 是否成功 |
| **major 跨版本** | ⚠️ 必看 changelog | 区分 "engines bump 无害" vs "API breaking" |
| **`react-native` 自身 major** | ❌ 不走 Dependabot | 手动 feature branch 升,本地完整测试 |
| **`peerDependencies` 收紧** | ❌ 不走 Dependabot | 影响消费者,要专门发版通告 |

### 何时关 + ignore

| 情形 | 操作 |
|---|---|
| PR yarn.lock 坏了 / 解析错误 | `@dependabot recreate` 重新生成;再不行 `@dependabot close` 等下周再试 |
| major 跨版本有 breaking | `@dependabot close` + 评论 `@dependabot ignore this major version` |
| yarn 4 跟某个包暂时不兼容 | 手动 close,本地手动升级调试 |

---

## 应急流程

### 手动触发发版(workflow_dispatch)

```
Actions → Release → Run workflow
  Use workflow from: main
  强制版本类型: 留空(自动推断)/ patch / minor / major
  → 绿按钮
```

适用场景:
- 自动触发的 paths 不命中,但确实想发(比如纯 RN 升级合并后)
- 想强制某个 bump 类型(自动推断给的不对,如 0.x 阶段想用 patch 而非 minor)
- CI 自动发版挂了,手动重试

### 关闭 / 跳过 Dependabot PR

- 单个 PR:评论 `@dependabot close` 或 UI 点 Close
- 永久 ignore 某依赖某版本:`@dependabot ignore this <version|minor version|major version|dependency>`
- 全局 ignore 规则(`.github/dependabot.yaml` 加 ignore 块):

```yaml
ignore:
  - dependency-name: '*'
    update-types: ['version-update:semver-major']   # 完全停掉所有 major
```

### 手动升级依赖(绕过 Dependabot)

适用 yarn 4 lockfile 解析有坑 / 想精确控制升级 / major 跨版本需手测:

```sh
git switch -c chore/manual-upgrade-<pkg>
yarn up "<pkg>@<version>"                    # 升单个
yarn up "react-native@0.85.3" "@react-native/*@0.85.3"   # 批量同前缀
yarn install
yarn lint && yarn typecheck && yarn test
# 手测后 push + PR
```

### 回滚版本

不推荐(npm 不能 unpublish 已发布超过 72h 的版本),但可:

- **deprecate** 某版本:`npm deprecate @unif/react-native-design@0.2.0 "包含 bug,请升 0.2.1"`(消费者 install 会看到 warning)
- **发新 patch 修问题**:`feat:` 改回去 / `fix:` 紧急修补,正常流水线发版

---

## 配置文件清单

| 文件 | 作用 |
|---|---|
| `.github/workflows/ci.yml` | CI 主流程,PR + push:main 时跑 lint/test/build×3 |
| `.github/workflows/release.yml` | 发版流水线,push:main 命中 paths 或手动触发 |
| `.github/actions/setup/action.yml` | composite action,Node + yarn install + cache,被两个 workflow 复用 |
| `.github/PULL_REQUEST_TEMPLATE.md` | PR template,自动套到所有新 PR |
| `.github/dependabot.yaml` | Dependabot 配置(weekly npm + monthly actions + group)|
| `package.json#release-it` | release-it 配置(commit msg / tag / npm publish / GH release)|
| `package.json#release-it.plugins.@release-it/conventional-changelog` | changelog 生成 + 落盘 `CHANGELOG.md` |
| `package.json#commitlint` | commit msg 校验规则(`@commitlint/config-conventional`)|
| `package.json#jest` | jest preset + `testEnvironment: node` 覆盖 |
| `lefthook.yml` | git hooks:pre-commit 跑 eslint + tsc,commit-msg 跑 commitlint |
| `GitHub Settings → Rules → Rulesets` | main branch protection(UI 配,不在仓库)|
| `GitHub Settings → General → Pull Requests` | Squash merge default + auto-delete head branches(UI 配)|
| `npmjs.com → 包 Settings → Publishing access → Trusted Publishers` | npm OIDC trusted publisher 绑定(UI 配)|

---

## 排查常见报错

### `Not authenticated with npm. Please npm login` (release-it 报)

**原因**:release-it 跑 `npm whoami` 预检查,OIDC 没持久登录,直接 abort。

**修法**:`package.json#release-it.npm.skipChecks: true`。已配,这条不该再出现。

---

### `Repository rule violations found for refs/heads/main` (GH013)

**原因**:试图直接 push 到 main,被 branch protection ruleset 拦。

**修法**:走 PR + Squash merge。**正确的反馈,不是 bug**。

如果是 release-it bot 推 release commit 被拦:Bypass list 加 `Repository role: Admin`。

---

### `scopeManager.addGlobals is not a function`(ESLint 报)

**原因**:yarn.lock 把 eslint 升到了 10.x,但代码用旧 plugin 期望 eslint 9 的 API。Dependabot rebase 过程可能搞坏 yarn.lock。

**修法**:`@dependabot recreate` 让 bot 完全重新生成 PR;不行就 close 等下次。

---

### Release workflow 跑了但没发版

**正常,不是 bug**。原因:最新 commit 是 `chore:` / `docs:` 等非 release-worthy 前缀,release-it 看到"无可发布变更"exit 0。

如果**应该发版但没发**:确认 commit 前缀是不是 `feat:` / `fix:` / 含 `BREAKING CHANGE:`。是的话看 release-it 日志,可能是 conventional-changelog plugin 解析出了问题。

---

### npm publish 失败 `403 Forbidden`

**原因**:Trusted Publisher 配置错。

**Checklist**:
- npm 包 Settings → Publishing access → Trusted Publishers 里 `workflow filename` 是否填的 `release.yml`(只填文件名,不带 `.github/workflows/` 前缀)
- `repository` / `organization` 名字是否正确
- workflow `permissions.id-token: write` 是否配了
- npm CLI 版本:run 日志看 `npm --version` ≥ 11.5.1

---

### `This branch is out-of-date with the base branch`(PR 上)

**原因**:Ruleset 配了 `Require branches to be up to date`,PR 落后于 main HEAD,必须先同步才能合。

**修法**:
- Dependabot PR:评论 `@dependabot rebase`
- 普通 PR:UI 点 **Update with rebase** 按钮(推荐,线性历史)或 **Update with merge commit**

---

## 不要做的事

- ❌ **本地跑 `yarn release`** —— 必须经 GitHub Actions workflow,避免 git/npm 不同步的脏状态(0.1.2 那次教训)
- ❌ **手 改 `CHANGELOG.md`** —— 由 release-it 维护,手改下次发版会被前置插入打乱
- ❌ **直接 push main** —— ruleset 拦着,无意义
- ❌ **`npm publish` 手动** —— 走 OIDC trusted publishing 后,本地没 npm 凭据
- ❌ **手 改 `data.ts`** —— icons 数据由 `scripts/build-icons.js` 生成
- ❌ **`release.yml` 加 `NPM_TOKEN` 回退**—— Trusted Publishing 是单一发版凭据,不要混杂方案
