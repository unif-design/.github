[← 索引](../AUTOMATION.md) · [← 总览](./01-overview.md) · [CI workflow →](./03-ci.md)

---

# 日常开发主流程

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

### 6. CI 6 个 check 必须全绿

| Check | 跑什么 | 阻塞合并 |
|---|---|---|
| `CI / actionlint` | 校验 workflow YAML / 表达式 / `run:` shell | ✅ |
| `CI / lint` | `yarn lint`(eslint + prettier)| ✅ |
| `CI / test` | `yarn test --maxWorkers=2 --coverage` | ✅ |
| `CI / build-library` | `yarn prepare`(bob build → `lib/`)| ✅ |
| `CI / build-android` | turbo 跑 example android 编译 | ✅ |
| `CI / build-ios` | turbo 跑 example iOS 编译(macos-latest)| ✅ |

ruleset 配了 6 个 check 为 required,缺一不可。

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


---

[← 索引](../AUTOMATION.md) · [← 总览](./01-overview.md) · [CI workflow →](./03-ci.md)
