[← 索引](../AUTOMATION.md) · [← Branch protection (Rulesets)](./05-branch-protection.md) · [安全扫描 →](./07-security.md)

---

# 依赖管理（人工升级）

## 组织决策

依赖升级由维护者明确发起、审查和合并，不让机器人自动创建或自动合并 PR：

- 各仓不保留 `.github/dependabot.yaml`。
- 各仓不保留 `.github/workflows/dependabot-auto-merge.yml` 或旧名 `dependabot-automerge.yml`。
- `scripts/sync-repo.sh` 每次同步都会主动移除上述文件，防止旧配置复活。
- `scripts/setup-repo.sh` 明确关闭 GitHub 的 Dependabot security updates，避免它绕过配置文件自动创建安全升级 PR。
- Dependabot alerts 保留为漏洞信号；发现告警后由维护者创建人工升级 PR。

这项约束只关闭自动改代码和自动开 PR，不关闭漏洞告警，也不影响维护者主动升级依赖。

## 人工升级 SOP

```text
1. 根据上游 release notes / changelog 明确升级目标和兼容性风险。
2. 从最新 main 创建 chore/manual-upgrade-<pkg> 分支。
3. 用 yarn up / yarn install 更新 manifest 与 lockfile，不手改 lockfile。
4. 审查依赖树、peerDependencies、Node / RN / 原生平台要求和生成文件 diff。
5. 跑仓库约定的 lint、typecheck、test、build 与必要的真机验证。
6. 创建普通 PR，说明升级原因、风险、验证证据和回退办法。
7. CI 与人工审查通过后 squash merge。
```

常用命令：

```sh
git switch -c chore/manual-upgrade-<pkg>
yarn up "<pkg>@<version>"
yarn install
yarn lint
yarn typecheck
yarn test
```

具体门禁以仓库根 `AGENTS.md`、`CONTRIBUTING.md` 和现有 CI 为准；不要因为升级看起来只是 patch 就省略验证。

## GitHub Actions 版本

workflow 的第三方 `uses:` 必须 pin 到 40 位 commit SHA，并保留版本注释：

```yaml
uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
```

升级步骤：

1. 从 Action 官方 release / tag 确认目标版本。
2. 核对该版本 tag 对应的完整 commit SHA，不使用浮动 `@vN` 或 `@main`。
3. 同时更新 SHA 和版本注释，审查 changelog 中的输入、权限和运行时变化。
4. 让 actionlint 与相关 workflow 集成门禁通过后再合并。

## 升级风险分级

| 类型 | 处理要求 |
|---|---|
| `@types/*` patch | 仍走人工 PR；至少跑 typecheck 与 test |
| 单个 dev tool patch / minor | 核对 Node engines、配置默认值和插件兼容性 |
| React Native patch / minor | 跑 example、Android、iOS 构建及必要真机验证 |
| major | 必看 changelog / migration guide，单独评估 breaking changes |
| `react-native` major | 独立升级任务，包含完整双端回归 |
| `peerDependencies` 收紧 | 评估所有消费者，按发布规则说明兼容性影响 |

不是所有 major 都一定破坏 API，但也不能只凭版本号判断。只提高 `engines.node` 下限和内部重构可能风险较低；API 重命名、默认值变化、架构重写则必须迁移和回归。

## `@unif/*` 互相引用不要用 caret

**规则：`@unif/*` 之间的 peer 与 install 一律写 `>=x.y.z` 下限，不写 `^x.y.z`。**

npm 的 caret 在 0.x 上会锁住次版本：

```text
^1.26.0   接受 1.26.0 ~ 1.99.99
^0.26.0   只接受 0.26.x
```

多数 `@unif/*` 包仍在 0.x，`^0.26.0` 会意外拒绝 0.27.0；`>=0.26.0` 才能表达组织内部包常用的最低版本语义。只有存在明确技术依据时才加上限，并把依据记录在代码或 PR 中。

## 漏洞告警处理

Dependabot alerts 只负责提示已知 CVE，不自动修改仓库。收到告警后：

1. 确认受影响版本范围、可利用条件和当前仓库是否真实使用该路径。
2. 选择最小安全版本，在人工分支中升级并执行完整门禁。
3. 在 PR 中关联告警，记录影响判断和验证证据。
4. 合并后确认告警关闭；若暂不能升级，记录补偿控制和复查日期。

---

[← 索引](../AUTOMATION.md) · [← Branch protection (Rulesets)](./05-branch-protection.md) · [安全扫描 →](./07-security.md)
