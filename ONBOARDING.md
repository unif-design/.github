# 新 repo 接入 unif-design 标准

> 历史资料：以下内容用于追溯迁移前的标准。当前工程接入与交付请使用[现行维护入口](README.md)。

本流程区分开发接入、公开交付和远端发布，文件同步完成不能替代后续验收。

从现有应用提取公共库时，先按[库提取与等价迁移](docs/14-library-extraction.md)核对行为边界、原生 SDK 及补丁归属，再执行本流程。工程模板接入与功能迁移分别验收。

## 前置条件

- `gh` CLI 和 Python 3 已安装，登录账号具有目标仓库的管理员权限
- `unif-design/.github` 仓库已 clone 到本地(因为脚本需要 `scripts/rulesets/*.json`)
- 目标 repo 已经 `gh repo create unif-design/<repo> --public`

## 接入步骤

### 1. 下发标准 workflow + 配置文件(sync-repo.sh)

先把标准 workflow 同步进新 repo 的工作树:

```sh
cd /path/to/unif-design/.github
./scripts/sync-repo.sh <repo-name>          # 默认目标 ../<repo-name>
```

脚本从 `templates/` 拷贝 `ci.yml` / `release.yml` / lefthook / PR&Issue 模板等,做变量替换(repo 名 / npm 包名 / Pages URL),按 native/JS + 有无 website 条件分发;同时主动移除已停用的 Dependabot 配置和自动合并 workflow。**不 commit / 不 push** —— review `git diff` 后自己 commit + 开 PR(详见 [13-sync](docs/13-sync.md))。

先执行只读接入检查，发现模板偏离或工作流依赖缺失时修复后再提交：

```sh
./scripts/check-repo.sh <repo-name>
```

`source` 检查允许尚未公开发布的候选包。未授权建站或发布的开发任务不因此扩大范围；公开交付另须通过下面的发行前置。

### 2. 提交同步文件并运行 CI

检查 step 1 产生的差异，按仓库交付流程提交并合入同步文件：

| 文件 | 由 sync 下发 | 说明 |
|---|---|---|
| `.github/workflows/ci.yml` | 强制覆盖 | 共享 CI 标准，采用范围及专属检查须核对 |
| `.github/workflows/release.yml` | 强制覆盖 | paths 按 native/JS 注入;npm 包必需 |
| `.github/workflows/pr-title.yml` / `pr-agent.yml` | 强制覆盖 | |
| `.github/workflows/deploy-docs.yml` | 条件分发 | 仅有 `website/` 的仓 |
| `.github/workflows/native-lint.yml` / `nightly-build-check.yml` / `.clang-format` | 条件分发 | 仅 native 仓(有手写 `.kt/.mm`,即 umeng / hms-scan);`native-lint` 是 required check,`nightly` 是 advisory canary |
| `lefthook.yml` / `SECURITY.md` / `.github/PULL_REQUEST_TEMPLATE.md` / `ISSUE_TEMPLATE/*` | 强制覆盖 / 部分仅缺时创建 | `lefthook.yml` 含 native 仓的 `clang-format` / `ktlint` pre-commit(非 native 仓 glob 不命中惰性无害) |
| `.pr_agent.toml` | 仅缺时创建 | 保留各仓 repo 特化,不覆盖 |
| `.github/dependabot.yaml` / `.github/workflows/dependabot-{auto-merge,automerge}.yml` | 主动移除 | 组织已停用机器人自动升级 PR |

先提交并执行 `.github/workflows/ci.yml`，确认包括 `verified` 在内的标准检查已注册，再配置下一步 ruleset。采用 `native-lint.yml` 时也需先注册 `lint-cpp`／`lint-kotlin`。旧仓升级按 [CI 启用步骤](docs/03-ci.md#main-复用已通过的-pr)分阶段完成，不能给尚无相应作业的仓库直接加入新 required check。

### 3. 跑 setup-repo.sh(GitHub 端配置)

仓库内的 `.github/` 文件定义 workflow，不会自动启用 GitHub 端保护。远端配置也属于接入模板：基础设置来自 `templates/repository-settings.json`，主分支规则来自 `scripts/rulesets/`，统一由 `setup-repo.sh` 核对和应用，不在各库另写配置逻辑。

```sh
cd /path/to/unif-design/.github
# 只读检查；有差异、权限不足或 CI 检查尚未注册时返回非零。
./scripts/setup-repo.sh <repo-name> --check
# 只补齐差异；相同设置不重复写入，修改后重新读取确认。
./scripts/setup-repo.sh <repo-name>
```

例:
```sh
./scripts/setup-repo.sh portal
```

脚本使用已有 gh 登录和 Python 3，先核对管理员权限及实际 CI 作业名称，再执行下列配置。403、网络错误或未知状态不会当作“尚未配置”；未注册必需检查时不执行写入。脚本不创建组织共用 App、Secrets 或 npm 发布绑定。

脚本管理的设置：

| 配置 | 详情 |
|---|---|
| Merge methods | 只允许 Squash merge |
| Auto-delete head branches | merge 后自动删源 branch |
| Branch Ruleset "protect main" | 必须 PR + 完整标准 CI 的 7 个 required checks（含 actionlint、verified；采用 Native Lint 时为 9 个）+ 禁 force push + Squash only + release-bot bypass。运行前须已注册对应作业 |
| Secret scanning + Push protection | enable |
| Private vulnerability reporting | enable(配合 SECURITY.md)|
| Dependabot security updates | ⊘ **disable**(只保留 alerts,不自动创建修复 PR)|
| CodeQL Default setup | ⊘ **disable**(主动关闭,理由见 [07-security.md](docs/07-security.md))|
| GitHub Pages(若有 deploy-docs.yml)| enable + Source=GitHub Actions |
| About → Website | 自动指向 Pages URL |

只有回读与模板一致才报告通过。检查范围限于脚本管理的仓库设置；npm 发布绑定、CI 运行结果和设备验收仍各自核对。

### 4. npm Trusted Publisher(npm 包专用)

只有发 npm 包的 repo 需要:

```
npmjs.com → 你的包 → Settings → Publishing access → Trusted Publishers
  Publisher: GitHub Actions
  Org / Repo: unif-design / <repo>
  Workflow filename: release.yml
```

真正首次包先按[首次 npm 引导](docs/04-release.md#首次-npm-引导)建立包身份，再配置发布绑定；不要把 registry 404 当作可以复用旧版本的证明。已有 App、组织 Secrets 和发布绑定按实际状态复用。

详见 [AUTOMATION.md](AUTOMATION.md) 发版机制段。

### 5. Topics(可选,提升发现性)

`repo Settings → About 齿轮 → Topics`:加 3-7 个标签,如:
- `react-native` / `typescript` / `design-system` / `ui-library` / `mobile`

## 公开交付前置

```sh
./scripts/check-repo.sh --release <repo-name>
# 在库根目录构建后核对真正打包的文件：
node .github/scripts/check-library.cjs pack
```

公开库必须解除 `private`、明确分发许可、配置 npm 发布和正式文档站。README 与详细文档按[内容分工](#readme-与详细文档)组织；接口语义、示例真实性及许可选择仍需人工审查，不能只靠标题和链接判定内容完成。

文档站采用真实 website workspace，构建须执行共享 LLM 生成器，具备类型检查与测试入口；根目录 docs 作为网站来源时，同步覆盖 CI 与部署触发路径。新 RN 库自动采用通用研发入口；只有已存在专项技能的库才引用对应能力技能，不编造技能名称。

采用新模板后，必需的 `actionlint` 作业从组织 main 只读核对模板与静态接入；`build-library` 检查真实 tarball 的公开出口。组织模板升级后出现偏离，须核对并同步对应变更，不能单仓绕过检查。尚未同步新模板的旧库不自动宣称已通过新门禁。

Release 取得发布 App token 前检查公开发行前置，发布后由独立作业核对新版本、registry 元数据和实际下载产物；没有新版本、发布跳过或 registry 核验失败都会失败。文档触发失败也会报告；部署成功后再检查网站与 llms 地址，npm 与网站分别验收。若版本已经发布但验收失败，使用 [仅恢复发行验收](docs/04-release.md#仅恢复发行验收)，不重复发版。

### README 与详细文档

README 的编写、与详细资料的内容分工、版本说明及文档站维护采用 `uni-skills` 的 `documentation`。公开交付时核对用途与支持范围、安装与最小调用、公开 API、示例、文档站、npm 和许可证入口，影响能否使用的前提应在入口可见。SDK 版本、补丁和原生配置仍以本库实际接入契约为准；文档编写不因此启动新库接入或发布。

## 接入后核对清单

| 项 | 怎么验证 |
|---|---|
| 直接 push main 被拦 | `git push origin main` 报 `GH013` |
| PR 必须 CI 全绿才合 | 开试探 PR 看 merge 按钮是否灰着 |
| Squash merge 是唯一选项 | PR 页面 merge 按钮下拉只有 "Squash and merge" |
| PR Agent 自动 review | 开 PR 后 ~3 分钟有 DeepSeek 评论 |
| Pages 站点可访问 | `https://unif-design.github.io/<repo>/`(若启用)|
| 模板和发行前置 | `check-repo.sh --release <repo-name>` 与 `setup-repo.sh <repo-name> --check` |
| npm 实际可用 | `node .github/scripts/check-library.cjs published`，核对本次版本与 tarball |
| README 与 API | 按公开交付要求审查真实用法和所有公开入口 |

## 改 ruleset / org 端配置

修 `scripts/rulesets/protect-main.json` 后，逐仓确认 workflow 和检查名称已经接入，再运行 `setup-repo.sh` 更新同名 ruleset；不能在检查注册前批量套用新模板。

## 重复执行与验证

先读后比较，相同设置不写入。普通差异只 PATCH 对应字段；`protect main` 同名唯一时更新，没有时创建，多个同名规则则停止。保留已有的额外必需检查和其他规则，不修改其他命名的 Ruleset；发布机器人豁免以组织模板为准，不给普通账号或管理员额外豁免。

安全开关已符合标准时跳过。只有存在文档部署 workflow 才检查 Pages，已一致的 Pages 和网站入口不重复配置。失败或回读仍有差异时返回非零，不报告全部完成。已有仓库先运行 `--check` 查看缺项，再明确执行应用模式。

## 限制(脚本搞不定的)

| 项 | 为什么 + 怎么办 |
|---|---|
| Org-level Secret 创建 | 一次性已配 `DEEPSEEK_API_KEY`,新 repo 自动继承 |
| Org-level Ruleset | 需要 GitHub Team plan;Free plan 走 repo-level(脚本已支持)|
| npm Trusted Publisher | 在 npmjs.com 端不属 GitHub API |
| 自定义域名 DNS | 在 DNS provider 端 |
| Topics 自动填 | 各 repo 内容不同,留给手配 |

这些占接入时间不到 5 分钟。
