# 新 repo 接入 unif-design 标准

接入流程从手配 ~30 分钟降到 ~10 分钟。

## 前置条件

- `gh` CLI 已安装,登录账号是 `unif-design` 的 admin
- `unif-design/.github` 仓库已 clone 到本地(因为脚本需要 `scripts/rulesets/*.json`)
- 目标 repo 已经 `gh repo create unif-design/<repo> --public`

## 接入步骤(~10 分钟)

### 1. Push 第一波代码 + CI workflow

新 repo 必须先有 `.github/workflows/ci.yml`,且**至少跑过一次**(成功或失败都行,GitHub 需要索引 check 名字)。否则 ruleset 的 required status checks 配置会失败。

参考 react-native-design 的 `.github/workflows/ci.yml` 结构。

### 2. 跑 setup-repo.sh

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
| Branch Ruleset "protect main" | 必须 PR + 5 个 required checks + 禁 force push + Squash only |
| Secret scanning + Push protection | enable |
| Private vulnerability reporting | enable(配合 SECURITY.md)|
| CodeQL Default setup(JS/TS only)| enable |
| GitHub Pages(若有 deploy-docs.yml)| enable + Source=GitHub Actions |
| About → Website | 自动指向 Pages URL |

跑完看到 `✅ <repo> GitHub 端配置完成`,GitHub 端就齐了。

### 3. Commit caller workflows 进 repo

从 react-native-design 复制以下文件到新 repo,根据需要调整:

| 文件 | 必需? |
|---|---|
| `.github/workflows/ci.yml` | ✅ 已经在 step 1 |
| `.github/workflows/pr-agent.yml`(5 行 caller)| 推荐 |
| `.github/workflows/release.yml` | npm 包必需 |
| `.github/workflows/deploy-docs.yml` | 有 docs 站才需要 |
| `.github/dependabot.yaml` | 推荐 |
| `.pr_agent.toml`(根目录,项目特有 prompt)| 可选 |

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
