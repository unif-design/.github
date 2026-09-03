[← 索引](../AUTOMATION.md) · [← 配置文件清单](./12-reference.md)

---

# 一键同步 workflow 模板(`scripts/sync-repo.sh`)

## 为什么需要

4 个包仓(design / camera / umeng / hms-scan)的 `ci.yml` / `release.yml` / PR 模板等**各 copy 一份**,长期 drift:有的 `ci.yml` 缺 `changes` 门控、有的 build-android 还用 zulu(踩 CDN 520)、相同 workflow 的实现不一致。

**根因**:workflow 文件本身没有「标准源」。`setup-repo.sh` 管 GitHub 端配置(ruleset / security / Pages),但 repo 内的 `.yml` 文件一直靠人肉复制。

`templates/` + `sync-repo.sh` 补这一块:**一份标准模板,一条命令下发到任意仓**。

## 跟 `setup-repo.sh` 的分工

| 脚本 | 管什么 | 怎么实现 |
|---|---|---|
| `setup-repo.sh <repo>` | **GitHub 端配置** —— merge methods / branch ruleset / secret scanning / 关闭 CodeQL / Pages | `gh api` PATCH/PUT,改 GitHub 服务端 |
| `sync-repo.sh <repo>` | **repo 内文件** —— workflow / lefthook / PR&Issue 模板 / SECURITY;四仓共享 Agent bootstrap;移除已停用的 Dependabot 自动化 | 拷贝 `templates/` + 变量替换 + 明确清理;命中四仓时调用 marker 级 Agent 同步,改目标仓工作树 |

两者互补:先 `sync-repo.sh` 把 `ci.yml` 等文件 commit 进 repo + 跑过一次(GitHub 索引 check 名),再 `setup-repo.sh` 配 ruleset(required checks 才挂得上)。

## 标准模板在哪

`unif-design/.github` 仓的 `templates/`:

```
templates/
├── actions/
│   └── setup/action.yml           # Node + Yarn package cache + immutable install
├── workflows/
│   ├── ci.yml                     # 四仓最优并集(见下)
│   ├── release.yml                # paths 区按 native/JS 注入
│   ├── pr-title.yml               # conventional-commits 标题校验
│   ├── pr-agent.yml               # caller,uses unif-design/.github 的 reusable workflow
│   ├── deploy-docs.yml            # 仅有 website/ 的仓
│   ├── native-lint.yml            # 仅 native 仓:lint-cpp(clang-format)+ lint-kotlin(ktlint),required check
│   └── nightly-build-check.yml    # 仅 native 仓:RN-next build canary,advisory(非 required)
├── .clang-format                  # 仅 native 仓:LLVM/2/120 最小稳定选项
├── lefthook.yml
├── pr_agent.toml                  # → .pr_agent.toml 基础版
├── SECURITY.md
├── PULL_REQUEST_TEMPLATE.md
├── AGENTS.md                     # camera / design / hms-scan / umeng 四仓共享 Agent bootstrap 唯一真相源
└── ISSUE_TEMPLATE/
    ├── bug_report.yml
    ├── config.yml
    └── feature_request.yml
```

### `ci.yml` —— 四仓最优并集

逐项从各仓真实跑通的写法里取最优:

| 项 | 取自 | 为什么 |
|---|---|---|
| actionlint `-shellcheck=shellcheck` + `shellcheck --version` | camera | 显式断言 shellcheck 存在,防 runner 变更导致 shell 检查静默降级 |
| `changes` paths-filter job(`dorny/paths-filter` v4)+ lint/test/build-* 挂 `needs: changes` | umeng / hms-scan | 纯文档 / 无关 PR 直接 skip build,省 CI |
| test-only 路径排除 + rolling Turbo/Gradle key | 统一标准 | 测试改动只跑 lint/test;新 commit restore 旧 cache 后仍可保存增量 |
| setup action 只缓存 Yarn package cache,始终 immutable install | 统一标准 | 避免多 workspace `node_modules` 大缓存与旧 install-state 假命中 |
| build-android `distribution: temurin` | design | runner toolcache 预装,避开 zulu/Azul CDN 偶发 520 |
| build-ios `macos-26` + `XCODE_VERSION: 26.5` + `RCT_USE_PREBUILT_RNCORE=1` | umeng / hms-scan | 26.5 修好 codegen `'memory' file not found`;prebuilt 省源码编译 5-10 分钟 |
| `setup-xcode` pin v1.7.0(`ed7a3b1...`) | design / camera | 最新可用 pin |

6 个 required check:`actionlint` / `lint` / `test` / `build-library` / `build-android` / `build-ios`。`changes` 永远 success、**不**进 required checks。**native 仓**(umeng / hms-scan)另发 `native-lint.yml`,再加 `lint-cpp` / `lint-kotlin` = 8 个(见下方覆盖策略的「条件分发」)。

## 用法

```sh
cd /path/to/unif-design/.github
./scripts/sync-repo.sh <repo-name> [target-repo-path]
```

- `<repo-name>`:repo 名(如 `react-native-design`),用于 `{{REPO}}` / URL 替换
- `[target-repo-path]`:目标仓本地工作树,默认 `../<repo-name>`(兄弟目录)

例:

```sh
./scripts/sync-repo.sh react-native-hms-scan
```

脚本**只改目标仓工作树,不 commit / 不 push** —— 跑完报告 `git status` + `git diff --stat`,改动留给你 review,各仓自己开 PR。全量 `sync-repo.sh` 仅为 `react-native-camera` / `react-native-design` / `react-native-hms-scan` / `react-native-umeng` 调用 `sync-agent-standards.sh`,其他仓明确跳过;后者也不 commit / 不 push。

## 变量替换

| 占位符 | 替换为 | 来源 |
|---|---|---|
| `{{REPO}}` | repo 名 | 第一参数 |
| `{{NPM_PKG}}` | npm 包名 | 目标 `package.json` 的 `name`,读不到 fallback `@unif/<repo>` |
| `{{PAGES_URL}}` | `https://unif-design.github.io/<repo>/` | 拼出来 |

## 覆盖策略(关键)

**workflow 文件强制统一,有 repo 特化的配置保留**:

| 类别 | 文件 | 行为 |
|---|---|---|
| **强制覆盖** | `ci.yml` / `.github/actions/setup/action.yml` / `release.yml` / `pr-title.yml` / `pr-agent.yml` / `lefthook.yml` / `SECURITY.md` / `ISSUE_TEMPLATE/{bug_report,config}.yml` | 每次 sync 覆盖(统一标准,不允许单仓 drift) |
| **主动移除** | `.github/dependabot.yaml` / `.github/workflows/dependabot-auto-merge.yml` / `.github/workflows/dependabot-automerge.yml` | 每次 sync 删除，保证机器人自动 PR 和旧自动合并 workflow 不会复活 |
| **marker 级覆盖(仅四仓)** | camera / design / hms-scan / umeng 根 `AGENTS.md` 的 `BEGIN/END UNIF REACT NATIVE STANDARD` 共享 bootstrap | 每次 sync 仅替换 marker 间内容;`templates/AGENTS.md` 是四仓共享 Agent bootstrap 唯一真相源,完整标准在 `unif-design/skills` 的 `rn-library` Skill,marker 外的仓库特有规则保留;非四仓跳过 |
| **仅缺时创建** | `PULL_REQUEST_TEMPLATE.md` / `.pr_agent.toml` / `ISSUE_TEMPLATE/feature_request.yml` | 目标已存在则跳过(保留各仓 repo 特化:PR 模板的各仓 checklist 如 umeng 微信分享项 / camera 的 vision-camera 分组 / umeng 的 TurboModule review 规则 等) |
| **条件分发** | `deploy-docs.yml` | 仅当目标有 `website/` 目录 |
| **条件分发(native)** | `native-lint.yml` / `nightly-build-check.yml` / `.clang-format` | 仅当目标有手写 native 源码(`HAS_NATIVE_SRC`,见下),即 umeng / hms-scan |
| **按 native/JS** | `release.yml` 的 `on.push.paths` | 目标有 `*.podspec` → `src/ios/android/podspec`;纯 JS → `src/scripts`。**均不含 package.json/yarn.lock**(workspace 登记 + 依赖升级会连带改它们,不该触发发版)|

> 为什么 `.pr_agent.toml` 不强制覆盖:它带各仓特有 review prompt。强制覆盖会抹掉特化，所以模板只是 base，sync 只补缺、不动已有。

> 为什么四仓的 `AGENTS.md` 不整文件强制覆盖:根文件还承载各仓特有规则。`sync-agent-standards.sh` 只刷新共享 bootstrap marker 区块;零 marker 时在 H1 后首次插入,只缺一侧、重复或倒序时拒绝写入,避免误伤本地规则。完整共享标准在 `unif-design/skills` 的 `rn-library` Skill。marker 脚本只更新 bootstrap,marker 外正文仍须语义审查。需要只更新四仓 Agent bootstrap 时,可独立运行 `./scripts/sync-agent-standards.sh <repo-name> [target-repo-path]`;非四仓不应用此共享区块。脚本只改目标工作树,不 commit / 不 push / 不创建 PR。

> **`HAS_NATIVE_SRC` 判据**:`sync-repo.sh` 用 `find` 看库本体的 `android/src` + `ios/` 下有没有手写 `.kt/.kts/.mm/.m/.cpp/.h`(crnl 布局下 example app 的 native 在 `example/` 下,不会误命中)。命中才下发 `native-lint.yml` / `nightly-build-check.yml` / `.clang-format`。判据用源码而非 `*.podspec`:design 纯 JS 但可能有壳 podspec,而 native lint 只对真有 `.kt/.mm` 的仓有意义。`react-native-camera`(vision-camera wrapper,无自有 native)同理不下发。

## 改了标准之后

改 CI / 发版标准 → 改 `unif-design/.github` 的 `templates/` → 对每个仓跑一遍 `sync-repo.sh <repo>` → review diff → 对四仓另审查 marker 外 `AGENTS.md` 语义 → 各仓 PR。历史 `docs/superpowers/specs/` 与 `docs/superpowers/plans/` 记录当时设计,不回写。**不要直接改某个仓的 `ci.yml`**(下次 sync 会被覆盖,且制造 drift)。

`pr-agent.yml` 是 caller,`uses: ...@main` 引用 org reusable workflow —— 改 reusable 逻辑(`.github/.github/workflows/pr-agent.yml`)对所有仓**立即**生效,不需要 sync。

---

[← 索引](../AUTOMATION.md) · [← 配置文件清单](./12-reference.md)
