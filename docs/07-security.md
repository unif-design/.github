[← 索引](../AUTOMATION.md) · [← 依赖管理 (Dependabot)](./06-dependencies.md) · [PR Review (AI 辅助) →](./08-pr-review.md)

---

# 安全扫描

GitHub 的免费安全检测里**启用 3 层**(repo Settings → Code security);**CodeQL 评估后不启用**(理由见下方子节)。安全姿态由 Secret scanning + Dependabot + Private vulnerability reporting 三层覆盖。

| 工具 | 检查什么 | 状态 |
|---|---|---|
| **Dependabot alerts** | 依赖里的已知 CVE | 默认 Enabled,不动 |
| **Dependabot security updates** | 漏洞依赖自动开 PR 升级 | 跟 dependabot.yaml 不同;Settings 单开 |
| **Secret scanning alerts** | 不小心 push 的 token / API key / 密码 | 公有 repo 免费,**已启用** |
| **Private vulnerability reporting** | 让 SECURITY.md 里"Report a vulnerability"按钮在 repo 上可用 | 跟 SECURITY.md 配套,**已启用** |
| **CodeQL Code scanning** | 代码静态扫描(SQL 注入 / XSS / 不安全 deserialization 等)| ⊘ **不启用**(详见下方子节)|

### CodeQL Code scanning —— 评估后不启用

`setup-repo.sh [4/6]` 主动把 Default setup PATCH 成 `not-configured`,四仓统一关闭。

**为什么不上 CodeQL**(小团队私有 RN bridge 库):

1. **JS/TS 层薄,安全价值低** —— 这批仓主要是 native bridge 胶水 + 薄 JS 包装层,没有 server / SQL / 反序列化 / 用户输入处理这些 CodeQL 真正擅长的攻击面,对 RN bridge 的实际告警基本为空。

2. **polyglot native 仓 Default setup 不友好** —— Default setup 的 language auto-detection 是**强制行为**:umeng / hms-scan 含 Kotlin / ObjC / C++,GitHub 会 auto-detect `java-kotlin` / `c-cpp` 并尝试跑,需要 build、要么拖慢要么 `No build command found` 失败,UI 上 deselect 对 auto-detected 语言**无效**。压成只跑 JS/TS 得切 Advanced setup 自己写 `codeql.yml`,又多一份要维护的 workflow。

3. **Default setup 语言列表会漂移** —— GitHub 定期重检测语言并自动更新 Default setup 的 languages:design 检测到 Ruby/Gemfile 会自动加回 `ruby`,camera 只 js-ts,各仓覆盖面无法锁死,维护成本 > 收益。

**结论**:关掉。代码层安全靠 review + lint + typecheck + Dependabot(依赖 CVE)兜底;真要上代码扫描,等有了实际 server / 敏感逻辑再**单仓**按需开 Advanced setup。

**已关闭(2026-06)**:四仓 `code-scanning/default-setup` 已 PATCH `not-configured`,`setup-repo.sh` 重跑保持关闭。

---


---

[← 索引](../AUTOMATION.md) · [← 依赖管理 (Dependabot)](./06-dependencies.md) · [PR Review (AI 辅助) →](./08-pr-review.md)
