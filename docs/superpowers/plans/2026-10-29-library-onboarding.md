# 公共库接入与 Logger 首次交付 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. 独立的模板与 Logger 实现按 dispatching-parallel-agents 分工，最终统一审查。

**Goal:** 新公共 RN 库经过可执行的接入、发布和文档验收；Logger 完成精简公共入口、MIT 分发准备及真实文档站接入。

**Architecture:** `.github` 是工程规则、脚本与 workflow 的唯一实现来源；skills 仅引用对应阶段入口。Logger 作为实际消费者接入，保留应用策略、文件目录、身份隔离与日志行为。

**Tech Stack:** Node.js 标准库、现有 Bash/Python 初始化脚本、GitHub Actions、TypeScript/Bob、Docusaurus、npm OIDC。

**Spec:** `ONBOARDING.md`、`docs/04-release.md`、`docs/13-sync.md`；Logger 的 `docs/FORMAT.md` 和公开日志契约。

## Global Constraints

- 不改 Portal、Design 或其他库的运行代码；不批量配置其他仓库。
- GitHub 默认使用 gh；保留发布 App 必要豁免，普通账号不得绕过保护。
- Logger 使用 MIT；版本首位保持 0，已存在的 0.1.1／0.1.2 标签不覆盖、不重发探测。
- npm 发布与 GitHub Release、文档部署分别验收；首次绑定与认证缺失不能伪装成功。
- 保留 skills 仓 icons 等并行修改，不手改已安装缓存。

## Review Focus

- private 包被发布器跳过却创建 Release：发布前拒绝，测试覆盖。
- exports 指向未打包文件或通配入口缺产物：检查真实 tarball 文件，测试覆盖。
- registry 404、网络错误或旧版本被当作新发布：核对新版本与可下载产物，测试覆盖。
- website 未登记 workspace 或部署失败被吞掉：配置与部署均失败退出，测试覆盖。
- 收敛入口使根入口提前加载原生 SDK或破坏 Web：通过真实打包消费者和 browser 条件验证。

## Task 1：组织共享检查

**Files:** `templates/scripts/check-library.cjs`、`scripts/check-library.test.cjs`、`scripts/check-repo.sh`、`scripts/sync-repo.sh`、`templates/workflows/{ci,release,deploy-docs}.yml`、组织验证 workflow 与接入文档。

**Interfaces:** 同步后使用 `node .github/scripts/check-library.cjs source|pack|release|published`；组织入口负责模板一致性与静态接入核对，远端仍用 `setup-repo.sh --check`。

- [ ] 用临时真实包夹具覆盖 private、出口遗漏、文档配置、发布结果错误。
- [ ] 实现静态接入、tarball 出口和 registry 发布验证；npm 公共发布意图必须明确。
- [ ] 接入现有 CI 作业与 Release；保留现有门禁名称，不增加无必要的权限。
- [ ] 文档定义 README 内容、首次 npm 前置、文档站与真实发布验收，不自动扩大受维护仓库。
- [ ] 通过契约测试、ShellCheck、Actionlint 和实际 Logger 接入检查。

## Task 2：Logger 公共入口与文档

**Files:** Logger 的 package.json、LICENSE、README.md、src/index.ts、相关入口与测试、example/App.tsx、website/、锁文件及必要文档。

**Interfaces:** 公开代码入口只保留根入口和 `/files`，保留 package.json 元数据；Web 文件适配使用 `/files` 的 browser 条件。

- [ ] 根入口提供日志、安装、脱敏及必要 console transport；backend 留内部，保持注入契约。
- [ ] 删除废弃的公开子入口映射并迁移实际示例、类型测试和文档；保持文件与身份行为。
- [ ] 采用 MIT、明确 public registry/access，保留版本由正式发布流程推进。
- [ ] README 提供安装、快速开始、API、文件生命周期、格式、支持范围、示例、网站与许可入口。
- [ ] 采用最小 Docusaurus 正式文档站和现有共享 llms 生成能力，不引入伪原生演示或无关 Web 兼容层。
- [ ] 验证 Lint、类型、回归、Bob、真实 tarball 消费、网站构建与浏览器页面。

## Task 3：规范引用与交付

**Files:** skills 源仓 `skills/code-development/references/library-onboarding.md` 及直接关联的评估材料；平台状态表仅更新 Logger 相关事实。

- [ ] skills 引用共享脚本与验收来源，不复制检测实现或每条配置规则。
- [ ] 核对首次 npm 的正式引导条件与已登录能力；缺少绑定或交互认证时明确需要用户完成的最小步骤。
- [ ] 按授权完成共享模板及 Logger 的 PR、CI、合并、文档部署和 npm 发布；严格区分已完成与尚缺外部前置。
- [ ] 回读 main/tag/registry/站点与本地状态，清理已合并且没有新增工作的任务分支。
