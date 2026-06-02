# 新 repo 接入 unif-design 标准

接入流程从手配 ~30 分钟降到 ~10 分钟。

## 前置条件

- `gh` CLI 已安装,登录账号是 `unif-design` 的 admin
- `unif-design/.github` 仓库已 clone 到本地(因为脚本需要 `scripts/rulesets/*.json`)
- 目标 repo 已经 `gh repo create unif-design/<repo> --public`

## 接入步骤(~10 分钟)

### 1. 下发标准 workflow + 配置文件(sync-repo.sh)

先把标准 workflow 同步进新 repo 的工作树:

```sh
cd /path/to/unif-design/.github
./scripts/sync-repo.sh <repo-name>          # 默认目标 ../<repo-name>
```

脚本从 `templates/` 拷贝 `ci.yml` / `release.yml` / dependabot / lefthook / PR&Issue 模板等,做变量替换(repo 名 / npm 包名 / Pages URL),按 native/JS + 有无 website 条件分发。**不 commit / 不 push** —— review `git diff` 后自己 commit + 开 PR(详见 [13-sync](docs/13-sync.md))。

新 repo 必须先有 `.github/workflows/ci.yml`,且 **commit 进 repo + 至少跑过一次**(成功或失败都行,GitHub 需要索引 check 名字),否则下一步 ruleset 的 required status checks 配置会失败。**native 仓**(umeng / hms-scan,有手写 `.kt/.mm`)除 `ci.yml` 外还要 `native-lint.yml` 也 commit 进 repo + 至少跑过一次(GitHub 要先索引 `lint-cpp` / `lint-kotlin` 这俩 check),否则下一步 8-check ruleset 配置会失败。

### 2. 跑 setup-repo.sh(GitHub 端配置)

```sh
cd /path/to/unif-design/.github
./scripts/setup-repo.sh <repo-name>
```

例:
```sh
./scripts/setup-repo.sh portal
```

脚本会自动配:

| 配置 | 详情 |
|---|---|
| Merge methods | 只允许 Squash merge |
| Auto-delete head branches | merge 后自动删源 branch |
| Branch Ruleset "protect main" | 必须 PR + 6 个 required checks(含 actionlint;native 仓为 8 个,多 `lint-cpp` / `lint-kotlin`)+ 禁 force push + Squash only + release-bot bypass。脚本检测到 `native-lint.yml` 自动套 8-check 版 ruleset |
| Secret scanning + Push protection | enable |
| Private vulnerability reporting | enable(配合 SECURITY.md)|
| CodeQL Default setup(JS/TS only)| enable |
| GitHub Pages(若有 deploy-docs.yml)| enable + Source=GitHub Actions |
| About → Website | 自动指向 Pages URL |

跑完看到 `✅ <repo> GitHub 端配置完成`,GitHub 端就齐了。

### 3. Commit 同步下来的文件进 repo

step 1 的 `sync-repo.sh` 已经把这些文件落到工作树(无需再手动从 react-native-design 复制),review 后 commit + PR:

| 文件 | 由 sync 下发 | 说明 |
|---|---|---|
| `.github/workflows/ci.yml` | 强制覆盖 | 四仓最优并集 |
| `.github/workflows/release.yml` | 强制覆盖 | paths 按 native/JS 注入;npm 包必需 |
| `.github/workflows/pr-title.yml` / `pr-agent.yml` / `dependabot-auto-merge.yml` | 强制覆盖 | |
| `.github/workflows/deploy-docs.yml` | 条件分发 | 仅有 `website/` 的仓 |
| `.github/workflows/native-lint.yml` / `nightly-build-check.yml` / `.clang-format` | 条件分发 | 仅 native 仓(有手写 `.kt/.mm`,即 umeng / hms-scan);`native-lint` 是 required check,`nightly` 是 advisory canary |
| `lefthook.yml` / `SECURITY.md` / `.github/PULL_REQUEST_TEMPLATE.md` / `ISSUE_TEMPLATE/*` | 强制覆盖 / 部分仅缺时创建 | `lefthook.yml` 含 native 仓的 `clang-format` / `ktlint` pre-commit(非 native 仓 glob 不命中惰性无害) |
| `.github/dependabot.yaml` / `.pr_agent.toml` | 仅缺时创建 | 保留各仓 repo 特化,不覆盖 |

### 4. npm Trusted Publisher(npm 包专用)

只有发 npm 包的 repo 需要:

```
npmjs.com → 你的包 → Settings → Publishing access → Trusted Publishers
  Publisher: GitHub Actions
  Org / Repo: unif-design / <repo>
  Workflow filename: release.yml
```

详见 [AUTOMATION.md](AUTOMATION.md) 发版机制段。

### 5. Topics(可选,提升发现性)

`repo Settings → About 齿轮 → Topics`:加 3-7 个标签,如:
- `react-native` / `typescript` / `design-system` / `ui-library` / `mobile`

## 接入后核对清单

| 项 | 怎么验证 |
|---|---|
| 直接 push main 被拦 | `git push origin main` 报 `GH013` |
| PR 必须 CI 全绿才合 | 开试探 PR 看 merge 按钮是否灰着 |
| Squash merge 是唯一选项 | PR 页面 merge 按钮下拉只有 "Squash and merge" |
| PR Agent 自动 review | 开 PR 后 ~3 分钟有 DeepSeek 评论 |
| Pages 站点可访问 | `https://unif-design.github.io/<repo>/`(若启用)|
| README badges 等等 | 各 repo 自己 README 维护 |

## 改 ruleset / org 端配置

修 `scripts/rulesets/protect-main.json` → 跑 `setup-repo.sh` 重新 PATCH 同名 ruleset(脚本幂等),所有已接入 repo 重跑一遍即可同步。

## 重跑 setup-repo.sh 安全吗

**安全**。所有 API 调用都是 PATCH / 创建-或-更新,不会破坏现有配置:
- Repo Settings 重设同样值
- Ruleset 同名存在则 PUT 更新,不存在则 POST 新建
- Security features 已 enable 重 enable 一次也无副作用
- CodeQL Default setup 重配会保持 query suite / languages 不变

跑多次幂等。

## 限制(脚本搞不定的)

| 项 | 为什么 + 怎么办 |
|---|---|
| Org-level Secret 创建 | 一次性已配 `DEEPSEEK_API_KEY`,新 repo 自动继承 |
| Org-level Ruleset | 需要 GitHub Team plan;Free plan 走 repo-level(脚本已支持)|
| npm Trusted Publisher | 在 npmjs.com 端不属 GitHub API |
| 自定义域名 DNS | 在 DNS provider 端 |
| Topics 自动填 | 各 repo 内容不同,留给手配 |

这些占接入时间不到 5 分钟。
