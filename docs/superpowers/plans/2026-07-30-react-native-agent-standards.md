# React Native Agent Standards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `.github` 建立可幂等同步的 React Native 库共享 Agent 标准,并让四个目标仓以 `AGENTS.md` 为唯一指令正文。

**Architecture:** `.github/templates/AGENTS.md` 保存带 marker 的共享区块,专用 Bash 脚本只替换目标根 `AGENTS.md` 中该区块。各仓保留本地正文,`CLAUDE.md` 仅导入 `AGENTS.md`;现有 `sync-repo.sh` 复用专用脚本,不负责 commit 或 push。

**Tech Stack:** Markdown、Bash、Git、ShellCheck、GitHub pull requests

## Global Constraints

- `.github` 必须在 `feat/react-native-agent-standards` 分支实施,不得直接修改 `main`。
- `react-native-hms-scan` 从干净 `main` 创建独立任务分支。
- `react-native-camera`、`react-native-design`、`react-native-umeng` 保留当前任务分支和现有改动。
- 不覆盖、暂存或提交任何无关文件。
- 共享区块不能覆盖仓库特有的定位、命令、架构、测试和平台规则。
- 四仓 `CLAUDE.md` 最终必须精确为一行 `@AGENTS.md`。
- 同步脚本不执行 `git add`、commit、push 或 PR。
- 已接受的 RNGH 3 / Carousel 5 例外只能窄放行,不得建议全局忽略 peer dependency。

---

## 文件结构

- `.github/templates/AGENTS.md`: 四仓共享的受控 Agent 标准区块。
- `.github/scripts/sync-agent-standards.sh`: agents-only 渲染、插入和更新脚本。
- `.github/scripts/sync-agent-standards.test.sh`: 临时 fixture 上的行为测试。
- `.github/scripts/sync-repo.sh`: 现有全量同步入口,调用 agents-only 脚本。
- `.github/README.md`: 标准源和手工同步入口。
- `.github/docs/13-sync.md`: 受控区块、覆盖边界和验证说明。
- 四仓 `AGENTS.md`: 共享区块 + 仓库特有正文。
- 四仓 `CLAUDE.md`: 单行导入。

### Task 1: 为 agents-only 同步写失败测试

**Files:**

- Create: `scripts/sync-agent-standards.test.sh`
- Test: `scripts/sync-agent-standards.test.sh`

**Interfaces:**

- Consumes: 计划中的命令 `scripts/sync-agent-standards.sh <repo-name> <target-path>`。
- Produces: 对首次插入、替换、幂等、映射、本地正文保留和坏 marker 拒绝的可执行契约。

- [ ] **Step 1: 写临时 fixture 测试**

测试用 `mktemp -d` 创建最小目标仓,写入 H1、本地章节和
`{"name":"@unif/react-native-camera"}`;调用尚不存在的同步脚本。断言:

```sh
grep -Fq '<!-- BEGIN UNIF REACT NATIVE STANDARD -->' "$target/AGENTS.md"
grep -Fq '`react-native-camera`' "$target/AGENTS.md"
grep -Fq '`../skills/skills/camera/`' "$target/AGENTS.md"
grep -Fq '## 本仓规则' "$target/AGENTS.md"
```

重复执行后比较 `shasum` 不变。另建只有 BEGIN marker 的 fixture,断言脚本返回非零且文件
hash 不变;再把包名改成 `@unif/react-native-design`,断言以 camera 参数同步时拒绝写入。

- [ ] **Step 2: 运行测试并确认正确失败**

Run:

```sh
bash scripts/sync-agent-standards.test.sh
```

Expected: FAIL,原因是 `scripts/sync-agent-standards.sh` 尚不存在,不是 fixture 或语法错误。

- [ ] **Step 3: 提交 RED 测试**

```sh
git add scripts/sync-agent-standards.test.sh
git commit -m "test: define agent standard sync contract"
```

### Task 2: 实现共享模板和同步脚本

**Files:**

- Create: `templates/AGENTS.md`
- Create: `scripts/sync-agent-standards.sh`
- Test: `scripts/sync-agent-standards.test.sh`

**Interfaces:**

- Consumes: `repo-name`,可选目标路径,模板占位符 `{{REPO}}`、`{{SKILL}}`。
- Produces: 只更新 marker 区块的目标 `AGENTS.md`;成功返回 0,结构错误返回非零。

- [ ] **Step 1: 写共享模板**

模板必须依次包含:

```text
marker begin
组织共享开发流程
任务开始:Skill 发现 + Git 状态 + 分支
实现与交付:验证 + PR CI + 合并后自动发布
website / llms.txt / {{SKILL}} Skill 联动
RNGH 3 / Carousel 5 已接受窄例外
共享与本仓规则边界
marker end
```

- [ ] **Step 2: 写最小同步脚本**

脚本用 `case` 固定映射,并校验目标 `package.json#name` 等于映射中的包名:

```sh
react-native-camera) skill=camera; package='@unif/react-native-camera' ;;
react-native-design) skill=design; package='@unif/react-native-design' ;;
react-native-hms-scan) skill=hms-scan; package='@unif/react-native-hms-scan' ;;
react-native-umeng) skill=umeng-share; package='@unif/react-native-umeng' ;;
*) exit 2 ;;
```

渲染到临时文件后,先验证 marker 数量。未接入时插入 H1 后;已接入时原位替换;任何坏
marker 在写目标文件前退出。

- [ ] **Step 3: 运行测试并确认通过**

Run:

```sh
bash scripts/sync-agent-standards.test.sh
bash -n scripts/sync-agent-standards.sh scripts/sync-agent-standards.test.sh
```

Expected: PASS,重复运行无 diff,坏 marker fixture 被拒绝。

- [ ] **Step 4: 运行 ShellCheck**

Run:

```sh
shellcheck -x scripts/sync-agent-standards.sh scripts/sync-agent-standards.test.sh
```

Expected: 0 warnings / errors。

- [ ] **Step 5: 提交实现**

```sh
git add templates/AGENTS.md scripts/sync-agent-standards.sh
git commit -m "feat: add shared React Native agent standards"
```

### Task 3: 接入现有同步入口并更新维护文档

**Files:**

- Modify: `scripts/sync-repo.sh`
- Modify: `README.md`
- Modify: `docs/13-sync.md`
- Test: `scripts/sync-agent-standards.test.sh`

**Interfaces:**

- Consumes: Task 2 的 agents-only 脚本。
- Produces: 全量同步时必定刷新共享区块,同时保留 agents-only 独立入口。

- [ ] **Step 1: 在 `sync-repo.sh` 调用专用脚本**

在强制统一阶段调用:

```sh
"$SCRIPT_DIR/sync-agent-standards.sh" "$REPO" "$TARGET"
```

文档明确 AGENTS 使用 marker 级覆盖,不同于整文件强制覆盖。

- [ ] **Step 2: 更新 README 与 sync 文档**

记录:

- `templates/AGENTS.md` 是共享区块唯一真相源。
- `sync-agent-standards.sh` 只改共享区块。
- 仓库特有规则仍在各仓根 `AGENTS.md`。
- 两个同步脚本均不 commit、不 push。

- [ ] **Step 3: 验证**

Run:

```sh
bash scripts/sync-agent-standards.test.sh
bash -n scripts/*.sh
shellcheck -x scripts/*.sh
git diff --check
```

Expected: 全部通过。

- [ ] **Step 4: 提交集成**

```sh
git add scripts/sync-repo.sh README.md docs/13-sync.md
git commit -m "docs: route shared agent standard sync"
```

### Task 4: 同步四仓并统一指令真相源

**Files:**

- Modify: `../react-native-hms-scan/AGENTS.md`
- Modify: `../react-native-camera/AGENTS.md`
- Modify: `../react-native-camera/CLAUDE.md`
- Modify: `../react-native-design/AGENTS.md`
- Modify: `../react-native-design/CLAUDE.md`
- Modify: `../react-native-umeng/AGENTS.md`
- Modify: `../react-native-umeng/CLAUDE.md`

**Interfaces:**

- Consumes: Task 2 的共享模板和同步脚本;三个旧仓当前 `CLAUDE.md` 正文。
- Produces: 四仓共享区块;三个旧仓完整 `AGENTS.md`;四仓单行 `CLAUDE.md`。

- [ ] **Step 1: 为 hms-scan 创建分支**

```sh
git switch -c docs/sync-react-native-agent-standards
```

- [ ] **Step 2: 原子迁移 camera / design / umeng**

每仓先重新确认 `AGENTS.md`、`CLAUDE.md` 无并发 diff。将当前 `CLAUDE.md` 完整正文迁入
`AGENTS.md`,首行改为 `# AGENTS.md`;将 `CLAUDE.md` 改为:

```markdown
@AGENTS.md
```

迁移时修正旧 Skill 映射为 `camera`、`design`、`umeng-share`,不得复制已失效的
`unif-*` 路径。

- [ ] **Step 3: 运行 agents-only 同步**

```sh
scripts/sync-agent-standards.sh react-native-camera /Users/liulijun/tongyi/design/react-native-camera
scripts/sync-agent-standards.sh react-native-design /Users/liulijun/tongyi/design/react-native-design
scripts/sync-agent-standards.sh react-native-hms-scan /Users/liulijun/tongyi/design/react-native-hms-scan
scripts/sync-agent-standards.sh react-native-umeng /Users/liulijun/tongyi/design/react-native-umeng
```

- [ ] **Step 4: 验证四仓结构**

逐仓运行:

```sh
test "$(wc -l < CLAUDE.md | tr -d ' ')" -eq 1
grep -Fxq '@AGENTS.md' CLAUDE.md
! rg -n 'CLAUDE\\.md' AGENTS.md
git diff --check -- AGENTS.md CLAUDE.md
```

Expected: 全部通过;共享 marker 各恰好一对。

- [ ] **Step 5: 分仓 review 和提交**

每仓只暂存 `AGENTS.md` / `CLAUDE.md`;若当前任务已明确占用这两个文件,把变更纳入当前
任务提交,不得从旁制造冲突。`hms-scan` 使用独立提交:

```sh
git add AGENTS.md
git commit -m "docs: add shared React Native agent standards"
```

### Task 5: 前向验证与 PR 交付

**Files:**

- Verify: `.github` 与四仓变更

**Interfaces:**

- Consumes: 完整共享标准。
- Produces: 可审查的功能分支和 PR。

- [ ] **Step 1: 前向验证提示词**

用不带预期答案的场景让独立 Agent 分别处理:

- 在 `main` 上收到紧急小改。
- 内部错误语义变化但 TypeScript API 未变。
- 已验证 RNGH 3 / Carousel 5 组合仍有 peer warning。

Expected: Agent 先建 / 保留合适任务分支;核对消费侧 Skill;不重复询问或阻塞已接受例外。

- [ ] **Step 2: 运行 `.github` 最终验证**

```sh
bash scripts/sync-agent-standards.test.sh
bash -n scripts/*.sh
shellcheck -x scripts/*.sh
git diff --check
git status --short
```

- [ ] **Step 3: 推送 `.github` 分支并创建 PR**

```sh
git push -u origin feat/react-native-agent-standards
gh pr create --base main --head feat/react-native-agent-standards
```

- [ ] **Step 4: 推送 hms-scan 分支并创建 PR**

```sh
git push -u origin docs/sync-react-native-agent-standards
gh pr create --base main --head docs/sync-react-native-agent-standards
```

- [ ] **Step 5: 报告其余三仓归属**

说明 camera / design / umeng 的共享区块分别进入哪个现有任务分支,以及 website /
llms.txt / 对应 Skill 的核对结论。
