[← 索引](../AUTOMATION.md) · [← 安全扫描](./07-security.md) · [Org 级共享基础设施 →](./09-org-sharing.md)

---

# PR Review(AI 辅助)

### 工具

`qodo-ai/pr-agent` GitHub Action,模型走 **DeepSeek V3**(`deepseek-chat`),通过 org 级 reusable workflow 集中维护。

| 维度 | 现状 |
|---|---|
| 模型 | DeepSeek V3(中文友好 + 成本 ~$0.01/PR)|
| 凭据 | `DEEPSEEK_API_KEY` org-level secret,所有 repo 共享 |
| 行为 | 新 PR 自动 review + 自动补 PR 描述;改进建议要手动 `/improve` 触发 |
| 是否阻断合并 | **否** —— 不进 required status checks,只是参考性评论 |

### 接入新 repo(5 行 caller)

```yaml
# 在 repo 加 .github/workflows/pr-agent.yml
name: PR Agent
on:
  pull_request:
    types: [opened, reopened, synchronize, ready_for_review]
  issue_comment:
    types: [created]

permissions:
  contents: read
  pull-requests: write
  issues: write

jobs:
  call:
    uses: unif-design/.github/.github/workflows/pr-agent.yml@main
    secrets:
      DEEPSEEK_API_KEY: ${{ secrets.DEEPSEEK_API_KEY }}
```

### prompt 分层

| 层 | 在哪 | 内容 |
|---|---|---|
| **通用 prompt**(baseline) | `unif-design/.github/.github/workflows/pr-agent.yml` 里 `PR_REVIEWER.EXTRA_INSTRUCTIONS` | TypeScript 类型 / 性能 / 可访问性 / 安全 |
| **项目特有 prompt**(增量)| 各 repo 根目录 `.pr_agent.toml` | 项目独有的规则,叠加在通用 baseline 之上 |

例(`react-native-design/.pr_agent.toml`):
```toml
[pr_reviewer]
extra_instructions = """
本仓库特有规则(在 org 通用规则之外):
- useThemedStyles(maker) 的 maker 必须在 styles.ts 模块顶层 export...
- 颜色 token role-based,亮暗 alpha 差异是有意的...
"""
```

### PR 评论里的命令

| 命令 | 作用 |
|---|---|
| `/review` | 重新跑一次 review(改了代码后)|
| `/improve` | 给具体 code suggestions(默认不自动跑)|
| `/describe` | 重新生成 PR 描述 |
| `/ask <问题>` | 问 AI 关于这个 PR 的具体问题 |
| `/update_changelog` | 让 AI 帮更新 CHANGELOG.md |

### 成本

DeepSeek V3 每 PR review ~$0.01。一个月 100 PR 不到 ¥10。换 `deepseek-reasoner`(R1 推理模型)能力更强但贵 3 倍。

### 不阻断合并的设计

`pr_agent` job 在 PR 页面显示但**不进 ruleset required status checks**。原因:
- AI 评论是建议性质,可能 false positive,不该当 merge gate
- DeepSeek API 临时挂 / 余额不足时不会卡死合并流程
- AI review 慢 + 每次 push 重新触发,加进 required 会让 PR 等很久

---


---

[← 索引](../AUTOMATION.md) · [← 安全扫描](./07-security.md) · [Org 级共享基础设施 →](./09-org-sharing.md)
