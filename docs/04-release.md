[← 索引](../AUTOMATION.md) · [← CI workflow](./03-ci.md) · [Branch protection (Rulesets) →](./05-branch-protection.md)

---

# 发版机制(Release workflow)

### 触发(`release.yml`)

```yaml
on:
  push:
    branches: [main]
    paths:                       # sync 按 native/JS 注入;native 仓为 src/ios/android/podspec
      - 'src/**'
      - 'scripts/**'             # 故意不含 package.json/yarn.lock —— website workspace 登记 + 依赖升级会连带改它们,不该触发发版(走手动 dispatch)
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
只有 chore: / docs: / 等   → 不发版,release-it exit 0
```

`workflow_dispatch` 时选了 `patch` / `minor` / `major` 就**强制**该类型、跳过自动推断;保持默认 `auto` 则走自动推断(release.yml 里 `INCREMENT != auto` 才把它传给 release-it)。

### 两套凭据,各管一段

发版要做两件需要授权的事,**刻意用两套独立凭据**,各自最小权限:

| 动作 | 凭据 | 为什么 |
|---|---|---|
| `npm publish` | **OIDC / Trusted Publishing**(`id-token: write`)| 无 long-lived token,npm 现场签发临时凭据 + provenance |
| `git push` release commit + tag 回 main | **GitHub App 临时 token** | main 受 ruleset 保护,默认 `GITHUB_TOKEN` 进不了 bypass(下节详述)|

两者职责不重叠:App token 只管 git push 那一段,`npm publish` 始终走 OIDC,不要混。

### Trusted Publishing(OIDC,npm publish 用)

| 配置点 | 值 / 位置 |
|---|---|
| workflow permissions | `contents: write` + `id-token: write` |
| npm 端 trusted publisher | npmjs.com → 包 Settings → Publishing access → Trusted Publishers,绑定 `unif-design/react-native-design` 的 `release.yml` |
| **不要**配 NPM_TOKEN secret | 走 OIDC 完全没有 long-lived token |
| `package.json#release-it.npm.skipChecks: true` | **必须** —— 跳过 `npm whoami` 预检查(OIDC 没持久登录)|
| `npm install -g "npm@^11"` step | **必须** —— OIDC 要求 npm CLI ≥ 11.5.1。**别写 `npm@latest`**:npm 的 engines 下限会先于 `.nvmrc` 钉的 node 往前跳,一跳就全组织发版同时断(2026-07-14 实测 npm@12 要 node ≥ 24.15,runner 是 24.13 → EBADENGINE)|

### push 回受保护 main —— 用 GitHub App token

**问题**:main 受 `protect main` ruleset 保护(必须走 PR),但 release-it 要**直接 push** `chore: release X.Y.Z` commit + tag 回 main。默认的 `GITHUB_TOKEN`(`github-actions[bot]`)**加不进 ruleset 的 bypass 列表** —— 它不是一个"安装的 GitHub App",ruleset 的 bypass Apps 选择器里只列出真正**安装到 repo 的 App**(如 Dependabot),没有 `github-actions[bot]` 这一项。

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
   - 生成 changelog,写入 `CHANGELOG.md`(根据 `@release-it/conventional-changelog.infile`),前置追加新版本段
   - git commit `chore: release X.Y.Z [skip ci]`(含 package.json + CHANGELOG.md)
   - git tag `vX.Y.Z`
   - `npm publish`(走 OIDC trusted publishing)
   - git push commit + tag(走 **App token**)
   - 创建 GitHub Release(走 **App token**)

### `release-it` 配置(`package.json#release-it`)

```jsonc
{
  "git": {
    // [skip ci] 防自触发死循环(见下节);release commit 本身不该再触发 release.yml
    "commitMessage": "chore: release ${version} [skip ci]",
    "tagName": "v${version}",
    "requireCommits": true   // 无新 conventional commit 时干净 exit 0,不报红叉
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

`requireCommits: true` —— 自上次 tag 以来没有任何 conventional commit 时,release-it 直接 **exit 0** 干净跳过,而不是抛错。否则手动触发 / paths 误命中却无可发内容时会留个红叉,污染 Actions 历史。

### 防自触发死循环

> ⚠️ **这是修好 App token push 之后才会暴露的坑,务必和 App token 一起配。**

**根因**:release-it 推回 main 的 `chore: release` commit 改了 `package.json`,正好命中 `release.yml` 的 `paths:`(含 `package.json`)→ 再次触发 `release.yml` → 再发一版 → 再 push → …… **无限发版**(react-native-design 实测刷出了 `0.4.0`~`0.4.33` 几十个空版本)。

> **2026-06 更新**:`package.json`/`yarn.lock` 已从 `release.yml` 的 `paths` 移除(它们会被 website workspace 登记 + 依赖升级连带改动,不该触发发版),`chore: release` commit 不再命中 paths → **这个根因已从源头堵死**。下面三道防线仍保留作冗余兜底(尤其手动 dispatch / src 改动场景)。

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
