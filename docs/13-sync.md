[← 索引](../AUTOMATION.md) · [← 配置文件清单](./12-reference.md)

---

# 一键同步 workflow 模板(`scripts/sync-repo.sh`)

## 为什么需要

4 个包仓(design / camera / umeng / hms-scan)的 `ci.yml` / `release.yml` / dependabot / PR 模板等**各 copy 一份**,长期 drift:有的 `ci.yml` 缺 `changes` 门控、有的 build-android 还用 zulu(踩 CDN 520)、dependabot auto-merge 文件名都不统一。

**根因**:workflow 文件本身没有「标准源」。`setup-repo.sh` 管 GitHub 端配置(ruleset / security / Pages),但 repo 内的 `.yml` 文件一直靠人肉复制。

`templates/` + `sync-repo.sh` 补这一块:**一份标准模板,一条命令下发到任意仓**。

## 跟 `setup-repo.sh` 的分工

| 脚本 | 管什么 | 怎么实现 |
|---|---|---|
| `setup-repo.sh <repo>` | **GitHub 端配置** —— merge methods / branch ruleset / secret scanning / CodeQL / Pages | `gh api` PATCH/PUT,改 GitHub 服务端 |
| `sync-repo.sh <repo>` | **repo 内文件** —— workflow / dependabot / lefthook / PR&Issue 模板 / SECURITY | 拷贝 `templates/` + 变量替换,改目标仓工作树 |

两者互补:先 `sync-repo.sh` 把 `ci.yml` 等文件 commit 进 repo + 跑过一次(GitHub 索引 check 名),再 `setup-repo.sh` 配 ruleset(required checks 才挂得上)。

## 标准模板在哪

`unif-design/.github` 仓的 `templates/`:

```
templates/
├── workflows/
│   ├── ci.yml                     # 四仓最优并集(见下)
│   ├── release.yml                # paths 区按 native/JS 注入
│   ├── pr-title.yml               # conventional-commits 标题校验
│   ├── pr-agent.yml               # caller,uses unif-design/.github 的 reusable workflow
│   ├── dependabot-auto-merge.yml  # 统一文件名 + approve 增强
│   └── deploy-docs.yml            # 仅有 website/ 的仓
├── dependabot.yaml                # 基础版
├── lefthook.yml
├── pr_agent.toml                  # → .pr_agent.toml 基础版
├── SECURITY.md
├── PULL_REQUEST_TEMPLATE.md
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
| build-android `distribution: temurin` | design | runner toolcache 预装,避开 zulu/Azul CDN 偶发 520 |
| build-ios `macos-26` + `XCODE_VERSION: 26.5` + `RCT_USE_PREBUILT_RNCORE=1` | umeng / hms-scan | 26.5 修好 codegen `'memory' file not found`;prebuilt 省源码编译 5-10 分钟 |
| `setup-xcode` pin v1.7.0(`ed7a3b1...`) | design / camera | 最新可用 pin |

6 个 required check:`actionlint` / `lint` / `test` / `build-library` / `build-android` / `build-ios`。`changes` 永远 success、**不**进 required checks。

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

脚本**只改目标仓工作树,不 commit / 不 push** —— 跑完报告 `git status` + `git diff --stat`,改动留给你 review,各仓自己开 PR。

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
| **强制覆盖** | `ci.yml` / `release.yml` / `pr-title.yml` / `pr-agent.yml` / `dependabot-auto-merge.yml` / `lefthook.yml` / `SECURITY.md` / `ISSUE_TEMPLATE/{bug_report,config}.yml` | 每次 sync 覆盖(统一标准,不允许单仓 drift) |
| **仅缺时创建** | `PULL_REQUEST_TEMPLATE.md` / `dependabot.yaml` / `.pr_agent.toml` / `ISSUE_TEMPLATE/feature_request.yml` | 目标已存在则跳过(保留各仓 repo 特化:PR 模板的各仓 checklist 如 umeng 微信分享项 / camera 的 vision-camera 分组 / umeng 的 TurboModule review 规则 等) |
| **条件分发** | `deploy-docs.yml` | 仅当目标有 `website/` 目录 |
| **按 native/JS** | `release.yml` 的 `on.push.paths` | 目标有 `*.podspec` → 含 `ios/android/podspec`;纯 JS → 只含 `src/scripts/package` |

> 为什么 `.pr_agent.toml` / `dependabot.yaml` 不强制覆盖:它们带各仓特有规则(review prompt / 依赖分组,且 dependabot 分组**顺序敏感**)。强制覆盖会抹掉特化。改这类文件走「模板是 base,各仓在 base 上手加特化」,sync 只补缺、不动已有。

## 改了标准之后

改 CI / 发版标准 → 改 `unif-design/.github` 的 `templates/` → 对每个仓跑一遍 `sync-repo.sh <repo>` → review diff → 各仓 PR。**不要直接改某个仓的 `ci.yml`**(下次 sync 会被覆盖,且制造 drift)。

`pr-agent.yml` 是 caller,`uses: ...@main` 引用 org reusable workflow —— 改 reusable 逻辑(`.github/.github/workflows/pr-agent.yml`)对所有仓**立即**生效,不需要 sync。

---

[← 索引](../AUTOMATION.md) · [← 配置文件清单](./12-reference.md)
