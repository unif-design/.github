[← 索引](../AUTOMATION.md) · [← CI workflow](./03-ci.md) · [Branch protection (Rulesets) →](./05-branch-protection.md)

---

# 发版机制(Release workflow)

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


---

[← 索引](../AUTOMATION.md) · [← CI workflow](./03-ci.md) · [Branch protection (Rulesets) →](./05-branch-protection.md)
