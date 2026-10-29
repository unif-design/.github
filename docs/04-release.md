[← 索引](../AUTOMATION.md) · [← CI workflow](./03-ci.md) · [Branch protection (Rulesets) →](./05-branch-protection.md)

---

# 发版机制(Release workflow)

### 触发(`release.yml`)

触发路径以各仓当前 `release.yml` 为准。共享模板只提供接入默认值，不能代替已经采用的仓库专属发布契约。当前维护范围如下：

| 仓库 | 自动触发路径 | 后续检查 |
|---|---|---|
| Design、Chat、Icons、Camera | `src/**`、`scripts/**` | Release 验证与版本推断 |
| HMS Scan | `src/**`、`ios/**`、`android/**`、`*.podspec` | Release 验证与版本推断 |
| Umeng | `package.json`、`src/**`、`scripts/**`、`ios/**`、`android/**`、`*.podspec`、`babel.config.js`、`tsconfig.build.json`、`tsconfig.json` | 发布契约检查可能判定无需发布；路径命中不等于发布成功 |

普通文档或 example 改动没有命中路径时，按本次发布授权手动 dispatch。下面是共享模板的 JS 库默认值：

```yaml
on:
  push:
    branches: [main]
    paths:                       # 仅表示模板默认值；已有仓库核对自己的配置
      - 'src/**'
      - 'scripts/**'
  workflow_dispatch:
    inputs:
      increment:
        description: '版本类型(auto = 走 conventional commits 自动推断)'
        default: auto
        type: choice
        options: [auto, patch, minor, major]   # 不能用空字符串 ''——actionlint 拒空 choice(见 03-ci)
```

两条路径:

1. **自动**:PR 合并到 main + 改动命中上述 paths → 工作流跑
2. **手动应急**:Actions → Release → Run workflow → 选 increment(`patch` / `minor` / `major`,或保持 `auto` 走自动推断)

### 版本推断逻辑

`release-it` + `@release-it/conventional-changelog` plugin 扫描自上次 tag 以来的所有 commits:

```
有 BREAKING CHANGE  → bump major
有 feat:            → bump minor
有 fix:             → bump patch
只有 test: / chore: / docs: / 等 → 当前 angular preset 仍建议 patch
```

提交类型、路径触发和发布资格是三件事。当前 `angular` preset 默认建议 patch，不能把维护类前缀当作“绝不发版”的保证。没有 tag 以来的新提交时由 `git.requireCommits` 拦截；Umeng 等仓库还会执行自己的发布契约检查。

`workflow_dispatch` 显式选择版本级别时按该级别发布；`auto` 使用自动推断。用户常规发版授权只覆盖 minor／patch，major 必须另获明确授权；不能把调用 dispatch 的技术能力当作大版本授权。

### 两套凭据,各管一段

发版要做两件需要授权的事,**刻意用两套独立凭据**,各自最小权限:

| 动作 | 凭据 | 为什么 |
|---|---|---|
| `npm publish` | **OIDC / Trusted Publishing**(`id-token: write`)| 无 long-lived token,npm 现场签发临时凭据 + provenance |
| `git push` release commit + tag 回 main | **GitHub App 临时 token** | main 受 ruleset 保护,默认 `GITHUB_TOKEN` 进不了 bypass(下节详述)|

两者职责不重叠:App token 只管 git push 那一段,正式版本的 `npm publish` 走 OIDC；首次包身份引导按下节处理，不复用 App token 作为 npm 凭据。

### Trusted Publishing(OIDC,npm publish 用)

| 配置点 | 值 / 位置 |
|---|---|
| workflow permissions | `contents: write` + `id-token: write` |
| npm 端 trusted publisher | npmjs.com → 包 Settings → Publishing access → Trusted Publishers,绑定 `unif-design/react-native-design` 的 `release.yml` |
| **不要**配 NPM_TOKEN secret | 走 OIDC 完全没有 long-lived token |
| `package.json#release-it.npm.skipChecks: true` | **必须** —— 跳过 `npm whoami` 预检查(OIDC 没持久登录)|
| `npm install -g "npm@^11"` step | **必须** —— OIDC 要求 npm CLI ≥ 11.5.1。**别写 `npm@latest`**:npm 的 engines 下限会先于 `.nvmrc` 钉的 node 往前跳,一跳就全组织发版同时断(2026-07-14 实测 npm@12 要 node ≥ 24.15,runner 是 24.13 → EBADENGINE)|

### 首次 npm 引导

仅用于已明确公开分发、包身份与历史已经核实、且尚不能配置 OIDC 的真正首次包。已有版本或历史标签必须保留；registry 404、查询失败和空列表不等于从未发布。

npm 已支持使用维护者登录会话通过 `npm stage publish` 创建新包，再配置 Trusted Publisher。它会公开 `0.0.0-stage` 占位包，真正候选进入待审队列；这不是正式版本发布成功，也不是 OIDC 验收。依据见 [npm 官方说明](https://docs.npmjs.com/staged-publishing/)及[首次包支持公告](https://github.blog/changelog/2026-10-02-npm-staged-publishing-now-supports-creating-new-packages/)。

1. 完成源码、许可证、测试和真实 tarball 审查，确认维护者具有组织发布权限。
2. 准备与下一正式版本不同的预发布引导候选；使用同一份已审核代码，并记录候选版本与摘要。待审版本占用版本号，不能暂存下一正式版本后又让 release-it 重发同版。
3. 使用已有 npm 登录会话暂存该候选，回读包身份与待审记录：

   ```sh
   npm stage publish <已审核候选.tgz> --access public --tag bootstrap --registry=https://registry.npmjs.org
   npm stage list <包名> --registry=https://registry.npmjs.org
   ```

4. 维护者完成 npm 的 2FA 并绑定本仓 `release.yml`，然后回读绑定；复用现有 GitHub App 与组织凭据，不创建临时 NPM_TOKEN：

   ```sh
   npm trust github <包名> --repository unif-design/<仓库名> --file release.yml --allow-publish --registry=https://registry.npmjs.org
   npm trust list <包名> --registry=https://registry.npmjs.org
   ```

5. 条件齐备后按授权合并或 dispatch，让正式新版本走既有 OIDC Release。核对 registry、下载产物、main 与标签，并验证文档部署。
6. 正式版本可用后，由维护者完成 2FA 拒绝剩余引导候选并回读队列；不把占位包或待审版本当作交付物，不删除正式版本来清理候选。

新绑定须在 npm 规定的有效期内完成第一次成功发布，当前为两天。身份、2FA、发布绑定或候选处置无法核实时，保留已完成产物，明确剩余条件；不得通过试发、覆盖标签或无依据地复用版本探测权限。

### 公开交付检查

共享脚本 `.github/scripts/check-library.cjs` 由组织 `templates/scripts/` 下发：

| 模式 | 检查范围 |
|---|---|
| `source` | 开发接入元数据、公开入口结构与存在的 website 接线；允许 private 候选 |
| `release` | 公开分发许可、非 private、npm/OIDC 配置、README 与正式文档站前置 |
| `pack` | 真正生成 tarball，核对包身份、main/types 和每个条件／通配 exports 目标 |
| `published` | 本次版本的官方 registry 元数据、下载产物身份、出口与完整性 |

Release 在申请发布 App token 前执行 `release`，验证后执行 `pack`。发布作业记录版本提交，独立验收作业检出该提交并执行 `published`；必须产生新版本且通过实际产物检查才算完成。共享 Release 设置 `NPM_CONFIG_ACCESS=public`，各库可显式配置相同的 publishConfig.access，不能使用 restricted。

registry 的 404、408、429、5xx 和网络／超时错误最多读取六次，重试间隔五秒，首次成功不等待。认证错误、无效 JSON、包身份或版本不符、下载地址及完整性问题立即失败，不能以重试替代正确的发布结果。

### 仅恢复发行验收

发布和验收使用独立作业，失败作业重跑无需重复执行已成功的发布作业。先核对 main、tag 和 npm 实际状态；若版本已经发布，仅重新核验现有版本并刷新 main 文档：

```sh
gh workflow run release.yml --ref main -f verify_only=true
```

此入口跳过 release-it、版本提升、提交和标签操作，也忽略 increment；它使用触发提交的 package.json 验证实际 npm 产物。不能用“重新发一个版本”或覆盖已有版本来修复单纯的验收延迟。若发布调用本身结果未知，先厘清实际状态再选择恢复步骤。

文档 dispatch 失败不再吞掉；它与 Deploy Docs 的构建、实际部署和公网地址核验分别报告。没有触发站点部署或站点验证失败时，不能称文档交付完成。

### push 回受保护 main —— 用 GitHub App token

**问题**:main 受 `protect main` ruleset 保护(必须走 PR),但 release-it 要**直接 push** `chore: release X.Y.Z` commit + tag 回 main。默认的 `GITHUB_TOKEN`(`github-actions[bot]`)**加不进 ruleset 的 bypass 列表** —— 它不是一个"安装的 GitHub App",ruleset 的 bypass Apps 选择器里只列出真正**安装到 repo 的 App**(如自建的 `unif-release-bot`),没有 `github-actions[bot]` 这一项。

**方案**(社区标准做法,semantic-release / changesets 同款):建一个 **org 级 GitHub App**(如 `unif-release-bot`),用它现场签发短期 token 替代 `GITHUB_TOKEN`,再把这个 App 加进 ruleset 的 bypass list。

| 步骤 | 配置 |
|---|---|
| 建 App | org Settings → Developer settings → GitHub Apps → New。权限**只给** `Repository permissions → Contents: Read and write`(push 够用,不给多余权限)|
| 装 App | 装到 repo,建议选 **All repositories**(org 内所有 repo 复用同一个 App)|
| 凭据存放 | App ID → org **variable** `RELEASE_APP_ID`;private key(`.pem` 全文)→ org **secret** `RELEASE_APP_PRIVATE_KEY`。**org 级存一次,所有 repo 共享** |
| workflow 里签发 token | `actions/create-github-app-token`(pin SHA)用上面的 ID + key 生成一个 **scope 限定到本 repo、约 1 小时过期**的 installation token |
| token 用法 | 替代 `GITHUB_TOKEN` 喂给 `actions/checkout` 的 `token:`(后续 git 操作才认这个身份)+ release-it 的 `GITHUB_TOKEN` env(git push commit / tag + 建 GH Release)|
| 进 bypass list | ruleset Bypass list 加这个 App,**mode 选 `Always`** —— release-it 直接 push 不走 PR,必须 `Always` 而非 `For pull requests`(详见 [Branch protection](./05-branch-protection.md))|

```yaml
- name: Generate App token
  uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3.2.0
  id: app-token
  with:
    app-id: ${{ vars.RELEASE_APP_ID }}
    private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

- name: Checkout
  uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
  with:
    fetch-depth: 0
    token: ${{ steps.app-token.outputs.token }}   # 后续 git push 才能 bypass ruleset
```

**为什么 App token 而不是 PAT / 临时关 ruleset**:

| 方案 | token 生命周期 | 归属 | 评价 |
|---|---|---|---|
| **GitHub App token** | 每次 run 现场签发,~1h 过期 | org 拥有 App,不绑个人 | ✅ 推荐 —— 无 long-lived secret,人走了也不失效 |
| Personal Access Token(PAT)| 长期有效(手动设过期)| 绑某个**个人**账号 | ❌ long-lived secret;owner 离职 / 改密码就挂;权限难收窄到单 repo |
| 发版前临时 disable ruleset | —— | —— | ❌ 有窗口期 main 完全裸奔;靠 workflow 自己开关易留半开状态 |

**committer 身份(让 release commit 显示 verified)**:用 `${{ steps.app-token.outputs.app-slug }}` 反查 App bot 的 numeric user id,拼成 `<id>+<slug>[bot]@users.noreply.github.com` 作为 commit email:

```yaml
- name: Resolve App bot identity
  id: bot
  env:
    GH_TOKEN: ${{ steps.app-token.outputs.token }}
    APP_SLUG: ${{ steps.app-token.outputs.app-slug }}   # 走 env 注入,不在 run 里直接 ${{ }} 插值
  run: |
    uid=$(gh api "/users/${APP_SLUG}[bot]" --jq .id)
    echo "name=${APP_SLUG}[bot]" >> "$GITHUB_OUTPUT"
    echo "email=${uid}+${APP_SLUG}[bot]@users.noreply.github.com" >> "$GITHUB_OUTPUT"
```

> ⚠️ **`app-slug` 必须走 `env:` 注入,不能在 `run:` 里直接 `${{ steps.app-token.outputs.app-slug }}` 插值** —— `${{ }}` 在 `run:` 里是先做字符串替换再交给 shell 执行,值里若含 shell 元字符就成了注入点。这是 GitHub 官方安全最佳实践:**所有 `${{ }}` 上下文值进 `run:` 一律先落 `env:`**。

### 工作流 step 顺序

1. **Generate App token** —— `actions/create-github-app-token`,产出 ~1h 过期、scope 限本 repo 的 token
2. Checkout(`fetch-depth: 0` → release-it 算 changelog 要全历史;`token:` 用 App token)
3. `./.github/actions/setup` —— Node + yarn install + cache
4. **Upgrade npm CLI** —— `npm install -g "npm@^11"`(锁 11.x,不追 npm 的 engines 漂移;理由见上表)
5. Verify —— `yarn lint && yarn typecheck && yarn test`(发版 gate)
6. Resolve App bot identity —— 反查 bot user id 拼 verified 邮箱
7. Configure git —— git user 设为 App bot(`unif-release-bot[bot]`)
8. **Release** —— `npx release-it [increment] --ci`,`GITHUB_TOKEN` env 喂 App token
   - bump `package.json` version
   - 跟踪网站生成产物的仓库执行 `after:bump`，按新版本生成 LLM 索引与 Markdown
   - `beforeRelease` 阶段将 changelog 写入 `CHANGELOG.md`(根据 `@release-it/conventional-changelog.infile`)，前置追加新版本段
   - `npm publish`(走 OIDC trusted publishing)
   - git commit `chore: release X.Y.Z [skip ci]`(含 package.json、CHANGELOG.md 和已跟踪的文档生成产物)
   - git tag `vX.Y.Z`
   - git push commit + tag(走 **App token**)
   - 创建 GitHub Release(走 **App token**)

当前 release-it 先发布 npm 包，再创建并推送版本提交。因此 npm 元数据的 `gitHead` 可指向版本提交之前的修订；验收同时核对包版本、完整性摘要、实际发布内容与 tag／main，不能仅凭 `gitHead` 与发布 tag 的提交号不同判定包内容不一致。

### `release-it` 配置(`package.json#release-it`)

```jsonc
{
  "hooks": {
    "after:bump": "node website/scripts/build-llms.js"
  },
  "git": {
    // [skip ci] 防自触发死循环(见下节);release commit 本身不该再触发 release.yml
    "commitMessage": "chore: release ${version} [skip ci]",
    "tagName": "v${version}",
    "requireCommits": true   // 自上次 tag 无新提交时拒绝重复发布
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

`requireCommits: true` 检查自上次 tag 以来是否有新提交，不按 `feat`／`fix` 过滤。当前默认 `requireCommitsFail: true`，无新提交会报错；以实际日志判断，不能把绿色工作流或无新增 tag 推断成发布成功。

上述 `hooks` 适用于跟踪网站生成产物的 Design、Icons：此时 package 版本已提升，随后 Git 阶段将已跟踪的 `website/static/llms.txt`、`llms-full.txt` 和 Markdown 产物纳入同一次发布提交；生成失败应中止发布。Chat、Camera、HMS Scan、Umeng 忽略这些产物，在本地与部署时生成，不配置该发布钩子，也不把本地缓存当作已提交文件。正式发布后核对 main、tag、npm 和线上索引；跟踪生成产物的仓库还须核对发布提交内的版本标记。

### 防自触发死循环

> ⚠️ **这是修好 App token push 之后才会暴露的坑,务必和 App token 一起配。**

**根因**:release-it 推回 main 的 `chore: release` commit 改了 `package.json`,正好命中 `release.yml` 的 `paths:`(含 `package.json`)→ 再次触发 `release.yml` → 再发一版 → 再 push → …… **无限发版**(react-native-design 实测刷出了 `0.4.0`~`0.4.33` 几十个空版本)。

> **2026-06 的处理**：当时从模板的触发路径移除了 `package.json`／`yarn.lock`。目前 Umeng 的发布契约需要监听 `package.json`，不能再声称所有仓库都不命中发布提交；下面的 `[skip ci]`、job 条件和并发约束仍须保留，并核对本仓专属检查。

**关键反直觉点**:在用 App token 修好 push 之前,这个循环**一直没发生** —— 因为 release commit 的 push 被 ruleset 拦住了(根本推不上去)。是 App token 让 CI 能写回受保护分支,**反而打开了死循环的闸门**。所以:

> **"让 CI 能写回受保护分支" 和 "防 CI 写回触发自己" 是必须同时做的一对。** 只做前者必炸。

**三道防线**(逐层兜底):

| # | 防线 | 配置 | 作用 |
|---|---|---|---|
| 1 | release commit 带 `[skip ci]` | `release-it.git.commitMessage: "chore: release ${version} [skip ci]"` | 这条 commit 的 push 被 GitHub Actions 直接跳过,不触发任何 workflow |
| 2 | job 级 `if` 兜底 | 见下方 | 万一 `[skip ci]` 失效,push 上来的 `chore: release` commit 仍被 skip |
| 3 | `concurrency` 串行 | `group: ${{ github.workflow }}` + `cancel-in-progress: false` | 同一时间只允许 1 个发版 run;发版跑到一半不能打断,故 `cancel-in-progress: false`。group 用 `${{ github.workflow }}` 动态命名(而非硬编码 `release`),避免跨 workflow 重名误取消 |

```yaml
jobs:
  release:
    # workflow_dispatch 无 head_commit → 前半 true 短路,手动发版不受影响
    if: "${{ github.event_name == 'workflow_dispatch' || !startsWith(github.event.head_commit.message, 'chore: release') }}"
```

```yaml
concurrency:
  group: ${{ github.workflow }}   # 动态命名,避免跨 workflow group 重名误取消
  cancel-in-progress: false
```

> 这个 `if` 表达式里 `'chore: release'` 含冒号,**必须给整个 `${{ }}` 套 YAML 双引号** —— 否则 release.yml YAML 解析直接失败、workflow 根本不注册。详见 [排查:release.yml if 表达式含冒号](./11-troubleshooting.md#releaseyml-if-表达式含冒号导致-workflow-不注册)。

**循环已经在跑时怎么止血** —— 见 [排查:发版死循环](./11-troubleshooting.md#发版死循环无限刷版本号)。

---


---

[← 索引](../AUTOMATION.md) · [← CI workflow](./03-ci.md) · [Branch protection (Rulesets) →](./05-branch-protection.md)
