# React Native CI Input Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让共享 CI 对 example 集成输入与 Yarn 运行时输入不再错误跳过 required jobs。

**Architecture:** 用独立 Node 契约测试解析 `ci.yml` 的 paths-filter,按 glob 的实际匹配结果验证代表性路径;模板采用 `example/**` 的保守覆盖。共享仓合并后,四个库只接收这份 CI 文件。

**Tech Stack:** GitHub Actions YAML、Bash、Node.js、dorny/paths-filter、actionlint、ShellCheck

## Global Constraints

- `main` 只通过 PR + CI 合入。
- 任意 `example/**` 必须命中 `shared` 与 `code`。
- `.yarnrc.yml` 和 `.yarn/releases/**` 必须命中 `shared`、`code` 与 `website`。
- 不修改或下发各仓 release workflow。
- 不手工发布 npm、创建 tag 或改版本号。

---

### Task 1: 用行为测试锁定过滤器输入

**Files:**
- Create: `scripts/ci-filter-contract.test.mjs`
- Modify: `scripts/ci-template.test.sh`
- Test: `scripts/ci-filter-contract.test.mjs`

**Interfaces:**
- Consumes: `templates/workflows/ci.yml` 中 `filters: |` 到 `lint` job 之间的 filter 定义。
- Produces: 退出码为 0 的路径匹配契约;任一代表性路径漏匹配时抛出 assertion。

- [ ] **Step 1: 写失败的路径匹配测试**

创建 Node 测试,解析 filter 名与单引号 glob。glob 转正则时先把 `**` 替换为哨兵,
再把 `*` 替换为 `[^/]*`,最后把哨兵替换为 `.*`。断言以下字面结果:

```js
const cases = [
  ['example/src/App.tsx', ['shared', 'code']],
  ['example/android/app/build.gradle', ['shared', 'code']],
  ['example/babel.config.js', ['shared', 'code']],
  ['.yarnrc.yml', ['shared', 'code', 'website']],
  ['.yarn/releases/yarn-4.11.0.cjs', ['shared', 'code', 'website']],
];
```

每个 case 对 expected filter 调用 `assert.equal(matches(filter, path), true)`。

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```sh
node scripts/ci-filter-contract.test.mjs
```

Expected: FAIL;第一条 example 或 Yarn 代表路径在旧模板中未命中要求的 filter。

- [ ] **Step 3: 把测试接入现有共享契约**

在 `scripts/ci-template.test.sh` 最终 PASS 前加入:

```sh
node "$script_dir/ci-filter-contract.test.mjs"
```

此时运行 `bash scripts/ci-template.test.sh` 仍必须因同一缺失契约失败。

- [ ] **Step 4: 提交测试**

```sh
git add scripts/ci-filter-contract.test.mjs scripts/ci-template.test.sh
git commit -m "test(ci): cover integration path filters"
```

### Task 2: 修正共享 CI 模板

**Files:**
- Modify: `templates/workflows/ci.yml`
- Test: `scripts/ci-filter-contract.test.mjs`

**Interfaces:**
- Consumes: Task 1 的路径匹配契约。
- Produces: 可同步到四仓的完整 `ci.yml` 模板。

- [ ] **Step 1: 加入最小 glob**

在 `shared` 与 `code` 中分别加入:

```yaml
- '.yarnrc.yml'
- '.yarn/releases/**'
- 'example/**'
```

在 `website` 中加入:

```yaml
- '.yarnrc.yml'
- '.yarn/releases/**'
```

- [ ] **Step 2: 运行目标测试并确认 GREEN**

```sh
node scripts/ci-filter-contract.test.mjs
bash scripts/ci-template.test.sh
```

Expected: 两条命令均退出 0。

- [ ] **Step 3: 运行共享仓完整验证**

```sh
bash -n scripts/*.sh
shellcheck scripts/*.sh
bash scripts/ci-template.test.sh
bash scripts/sync-agent-standards.test.sh
actionlint .github/workflows/*.yml templates/workflows/*.yml
git diff --check
```

Expected: 全部退出 0。

- [ ] **Step 4: 提交实现**

```sh
git add templates/workflows/ci.yml
git commit -m "fix(ci): cover integration inputs"
```

### Task 3: PR 交付并生成四仓同步输入

**Files:**
- Read: `scripts/sync-repo.sh`
- Read: `templates/workflows/ci.yml`

**Interfaces:**
- Consumes: Task 2 已验证模板。
- Produces: `.github` PR 与合并后的 canonical `ci.yml`。

- [ ] **Step 1: 推送任务分支并创建 Draft PR**

```sh
git push -u origin fix/ci-input-coverage
gh pr create --draft --base main --head fix/ci-input-coverage \
  --title "fix(ci): cover integration inputs"
```

- [ ] **Step 2: 等 required checks 通过**

```sh
gh pr checks --watch
```

Expected: 所有 required checks 通过,无 pending / failure。

- [ ] **Step 3: 转 Ready 并 squash merge**

```sh
gh pr ready
gh pr merge --squash --delete-branch
```

- [ ] **Step 4: 记录合并 SHA**

```sh
git -C /Users/liulijun/tongyi/design/.github pull --ff-only
git -C /Users/liulijun/tongyi/design/.github rev-parse HEAD
```

该 SHA 是四仓后续同步的唯一模板来源。
