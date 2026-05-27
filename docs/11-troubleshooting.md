[← 索引](../AUTOMATION.md) · [← 应急流程](./10-emergency.md) · [配置文件清单 + 不要做的事 →](./12-reference.md)

---

# 排查常见报错

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

**原因**:yarn.lock 把 eslint 升到了 10.x,但代码用旧 plugin 期望 eslint 9 的 API。Dependabot rebase 过程,或者你**手动 force-pushed** 到 dependabot branch 后(`yarn install` 解析到错误版本),都会搞坏 yarn.lock。

**修法**:`@dependabot recreate`(**不是** rebase)让 bot 完全重新生成 PR;不行就 close 等下次。

---

### `Cannot find name 'window'` / `Property 'clipboard' does not exist on type 'Navigator'`(`yarn prepare` 在 CI 失败)

**原因**:子项目(如 `website/` docs 站)用了 DOM API,但主项目 `tsconfig.json` 的 `lib: ["ESNext"]` 没含 `DOM`。问题是 `tsconfig.build.json` 自己定义的 `exclude` **覆盖**(不是合并)父 tsconfig 的 `exclude`,即使父排了 `website`,build.json 也丢。

**修法**:`tsconfig.build.json` 的 `exclude` 数组里**显式加** `website`(或任何子项目目录):

```json
{
  "extends": "./tsconfig",
  "exclude": ["example", "lib", "website"]
}
```

**通用教训**:TypeScript 的 `exclude` 字段在 extends 时是**覆盖**语义,不是合并。任何子 tsconfig 自己写 `exclude` 就必须 mirror 父全部 exclude 项。

---

### `commitlint` 报 `subject must not be sentence-case, start-case, pascal-case, upper-case`

**原因**:commit message subject 含**大写英文专有名词**。`commitlint/config-conventional` 默认规则要求 subject 全小写。

**踩坑案例**:
- ❌ `feat(components): Empty 加 icon prop`(组件名 `Empty` 大写)
- ✅ `feat(components): empty 加 icon prop`

**修法**:subject 全小写。组件名 / 类名 / Pascal-case 名字在 subject 里写小写,需要原名可以放 body / footer。或者配 `subject-case: [0]` 关掉规则(不推荐,大部分项目坚持惯例)。

---

### CodeQL Default setup 跑了未勾选的语言(polyglot repo 踩坑)

**根因**:Default setup 的 Language auto-detection 是**强制行为**,扫描 repo 内**所有 detect 到**的语言,UI 上 deselect checkbox **对 auto-detected 语言无效**。

**典型表现(RN 项目)**:
- repo 含 `example/android/` 的 Java/Kotlin 样板代码 → GitHub auto-detect 到
- 第一次 default run 跑 java-kotlin job 失败(`No build command found`)
- 即便 UI 上 Java/Kotlin 没勾选,backend 仍 enable

**修法**:
- **方案 A**(推荐):切到 **Advanced setup** —— Disable Default setup,自己写 `.github/workflows/codeql.yml`,显式 matrix language 只列 `javascript-typescript`,GitHub 完全照 yml 走不再 auto-detect
- **方案 B**:接受现状,Default setup 配 deselect 后,新 PR 的 CodeQL run 已经只跑 JS/TS(虽然 Security tab 上还有第一次失败的 stale alert,下次 push 自动清)

**通用教训**:Default setup 对单一语言项目最好(就 JS/TS 仓库),对 polyglot(混合 native + JS)用 Advanced setup 自己控制。

---

### `release-it --dry-run` 改了 `package.json` 的 version

**预期行为,不是 bug**。release-it 的 dry-run 模式**只跳过**外部副作用(npm publish / git push / GH Release),但**真跑** `npm version X.Y.Z`,会改 `package.json` 的 version 字段。

**修法**:dry-run 后还原:
```sh
git checkout -- package.json
```

dry-run 完别忘了还原,不然下一次 commit 会带上意外的 version bump。

---

### Release workflow 跑了但没发版

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


---

[← 索引](../AUTOMATION.md) · [← 应急流程](./10-emergency.md) · [配置文件清单 + 不要做的事 →](./12-reference.md)
