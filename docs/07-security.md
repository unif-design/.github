[← 索引](../AUTOMATION.md) · [← 依赖管理 (Dependabot)](./06-dependencies.md) · [PR Review (AI 辅助) →](./08-pr-review.md)

---

# 安全扫描

GitHub 提供 4 个层面的免费安全检测,**全部建议启用**(repo Settings → Code security):

| 工具 | 检查什么 | 状态 |
|---|---|---|
| **Dependabot alerts** | 依赖里的已知 CVE | 默认 Enabled,不动 |
| **Dependabot security updates** | 漏洞依赖自动开 PR 升级 | 跟 dependabot.yaml 不同;Settings 单开 |
| **CodeQL Code scanning** | 代码静态扫描(SQL 注入 / XSS / 不安全 deserialization 等)| 详见下方 CodeQL 子节 |
| **Secret scanning alerts** | 不小心 push 的 token / API key / 密码 | 公有 repo 免费,**建议启用** |
| **Private vulnerability reporting** | 让 SECURITY.md 里"Report a vulnerability"按钮在 repo 上可用 | 跟 SECURITY.md 配套,**建议启用** |

### CodeQL Code scanning

代码层面的安全扫描,跟 Dependabot 的"依赖漏洞扫描"互补。

### 启用方式(每个 repo 独立配置,**repo Settings**)

```
GitHub repo → Settings → Code security → Code scanning → Set up ▾
  选 "Default" → Enable CodeQL analysis
```

或直达 URL:`https://github.com/<org>/<repo>/security/code-scanning`。

**不需要写任何 yml**,GitHub 自动配 CodeQL workflow(检测语言 + 跑标准 query suite + 报告写入 Security tab)。**0 维护成本**。

### 模式选择

| 模式 | 含义 | 推荐 |
|---|---|---|
| **Default** | GitHub 自动管理,detect 语言、跑 default query suite、自动升级 | ✅ 推荐 —— 中小项目最佳 |
| **Advanced** | 自己写 `codeql-analysis.yml`,精细控制 query suite / 排除路径 / 触发条件 | 仅在 Default 满足不了需求时用 |

### Query suite 选择(Default 模式下的子选项)

| Query suite | 跑什么 | 推荐 |
|---|---|---|
| **Default** | 只跑标准安全查询,精挑误报少 | ✅ 推荐 —— 关键安全问题都 cover |
| **Security and quality** | Default + 代码质量查询(命名 / 复杂度 / 反模式等)| 误报会多,且质量已经有 lint / typecheck cover,通常不需要 |
| **security-extended**(Advanced 选项)| Default + 更激进的安全检查 | 大型 / 强合规项目用 |

**给当前项目**:选 **Default + Default query suite**。

### 结果在哪看

- **repo → Security tab → Code scanning alerts** —— 漏洞列表 / 严重度 / 影响范围
- **PR 上** —— 如果 PR 引入新漏洞,会自动评论;Default setup 会被加进 PR checks(可选,不阻塞)
- **每周 GitHub 邮件摘要** —— 如果有高危漏洞会通知

### 不需要做的

- ❌ 写 codeql-analysis.yml(Default 模式 GitHub 自动管)
- ❌ Schedule(Default 自动 weekly + on push to main)
- ❌ 把 CodeQL 加进 ruleset required(跟 PR Agent 同理,安全扫描是参考性,不该 gate merge)

---


---

[← 索引](../AUTOMATION.md) · [← 依赖管理 (Dependabot)](./06-dependencies.md) · [PR Review (AI 辅助) →](./08-pr-review.md)
