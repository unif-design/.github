# Unif 组织配置

集中维护 `unif-design` 的 CI、发布流程、开发入口和 GitHub 模板。

## 按任务查找

| 任务                    | 入口                                   |
| ----------------------- | -------------------------------------- |
| 接入新仓库              | [接入指南](ONBOARDING.md)              |
| 查看 CI、发布和分支规则 | [自动化标准](AUTOMATION.md)            |
| 核对及补齐远端设置      | [远端配置模板](templates/repository-settings.json)、[主分支规则](scripts/rulesets/) |
| 更新共享文件            | [同步说明](docs/13-sync.md)            |
| 接入 PR 自动审查        | [PR Review](docs/08-pr-review.md)      |
| 排查流水线问题          | [故障排查](docs/11-troubleshooting.md) |

## 同步到已有仓库

只更新 Camera、Design、HMS Scan、Umeng、Chat、Icons 的 AGENTS 共享入口：

```sh
./scripts/sync-agent-standards.sh react-native-design ../react-native-design
```

完整同步 workflow 与配置：

```sh
./scripts/sync-repo.sh react-native-design
```

同步会修改目标仓库文件；完整同步还会移除已停用的配置。执行后检查差异，各仓库自行提交和交付。本地文件同步不等于远端保护已启用；CI 作业注册后继续核对并应用远端模板：

```sh
./scripts/setup-repo.sh react-native-design --check
./scripts/setup-repo.sh react-native-design
```

`--check` 只读，应用模式只修改差异并回读确认。已有共用 App、Secrets 和 npm 发布绑定不由脚本重配，详情见接入指南。

只同步 LLM 文档生成实现（保留各库专属检查）：

```sh
node scripts/sync-llms.cjs react-native-design ../react-native-design
node scripts/sync-llms.cjs react-native-design ../react-native-design --check
```

## 维护来源

- [LLM 文档模板](templates/llms/)：五个文档站共用索引、路由与产物校验，Chat 保留代码 API 的专属转换；产物内容由各库文档和包声明生成。
- 单页来源注释只保留包名；包版本集中在 `llms.txt`、`llms-full.txt` 和包声明。只升级包版本时，`md/*.md` 与单页索引保持不变，避免每次发版重写全部文档。
- [远端设置模板](templates/repository-settings.json)和[主分支模板](scripts/rulesets/)：由 setup-repo 应用到指定仓库，不能靠复制 JSON 文件代替 GitHub 配置。
- [templates](templates/)：复制到各仓库的文件源；更改后需要重新同步。
- [AGENTS 模板](templates/AGENTS.md)：只指向 [unif-portal-dev-skills](https://github.com/unif-skill/unif-portal-dev-skills) 和项目开发资料。
- [共享 PR workflow](.github/workflows/pr-agent.yml)：引用 `@main` 的仓库在源更新后直接采用。
- [贡献指南](CONTRIBUTING.md)：组织通用贡献约定。
