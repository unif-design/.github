# Unif Design 自动化流程标准

`unif-design` 组织所有仓库共享的 CI / 发版 / 依赖管理 / PR review 标准。**以 `@unif/react-native-design` 仓库为参考实例**,其他 repo 套用同一套模式(配置文件路径、命令、ruleset 勾选项一致;只有 npm 包名 / specific scripts 名等需要替换)。

各 repo 在自己的 README / CONTRIBUTING 里加链接 `https://github.com/unif-design/.github/blob/main/AUTOMATION.md` 指过来即可,**不需要每个 repo 复制一份**。

## 渐进式阅读

按"先了解 → 然后日常用 → 按需深入专题 → 出问题查"的顺序组织:

### 入门(必读)

| # | 章节 | 一句话 |
|---|---|---|
| 1 | [总览](docs/01-overview.md) | 工作流全图 + 整套基础设施一页纸了解 |
| 2 | [日常开发主流程](docs/02-daily-workflow.md) | 从开 feature branch 到 Squash merge 后自动发版的完整 8 步 |

### 基础设施详解(按主题)

| # | 章节 | 一句话 |
|---|---|---|
| 3 | [CI workflow](docs/03-ci.md) | `changes` 门控 + 6 个 required job(actionlint / lint / test / build×3)+ pin SHA + 缓存策略 |
| 4 | [发版机制](docs/04-release.md) | `release.yml` + release-it + 两套凭据(OIDC publish + App token push)+ 防发版死循环 |
| 5 | [Branch protection (Rulesets)](docs/05-branch-protection.md) | Ruleset 4 项 + 发版 App 进 bypass + Repo Settings 配套勾选项 |
| 6 | [依赖管理 (Dependabot)](docs/06-dependencies.md) | 配置 / PR SOP / `@dependabot` 命令 / major 升级 case-by-case |
| 7 | [安全扫描](docs/07-security.md) | CodeQL / Secret scanning / Private vulnerability reporting / Dependabot alerts |
| 8 | [PR Review (AI 辅助)](docs/08-pr-review.md) | PR Agent + DeepSeek 自动 review,prompt 分层,命令清单 |
| 9 | [Org 级共享基础设施](docs/09-org-sharing.md) | `.github` 仓库 / org secret / reusable workflow / 新 repo 接入 |

### 用得到时再看

| # | 章节 | 一句话 |
|---|---|---|
| 10 | [应急流程](docs/10-emergency.md) | 手动触发发版 / 关闭 Dependabot PR / 回滚 / 本地 branch 清理 |
| 11 | [排查常见报错](docs/11-troubleshooting.md) | 真实踩过的坑 + 修法(release-it / 发版死循环 / YAML 冒号 / commitlint / yarn.lock / CodeQL polyglot ...)|
| 12 | [配置文件清单 + 不要做的事](docs/12-reference.md) | 所有配置文件路径速查 + 11 条 don't-list |
| 13 | [一键同步 workflow 模板](docs/13-sync.md) | `templates/` 标准源 + `scripts/sync-repo.sh` 下发(`ci.yml` 四仓最优并集 / 变量替换 / 覆盖 vs 保留特化)|

## 新 repo 接入

跑 `scripts/sync-repo.sh <repo>` 下发标准 workflow + `scripts/setup-repo.sh <repo>` 配齐 GitHub 端,详见 [ONBOARDING.md](ONBOARDING.md)(~10 分钟接入完成)。

## 维护

- **改流程标准** → 改对应 `docs/XX-*.md`
- **新增 / 删除章节** → 改本索引页 + 调整 docs/ 文件编号
- **每个 docs 文件有 nav header / footer**,跨章节跳转方便

读者从 README / CONTRIBUTING / CLAUDE.md 跳到本索引,按需进入子文档,不会一次面对 800+ 行单文件。
