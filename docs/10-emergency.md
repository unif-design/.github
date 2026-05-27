[← 索引](../AUTOMATION.md) · [← Org 级共享基础设施](./09-org-sharing.md) · [排查常见报错 →](./11-troubleshooting.md)

---

# 应急流程

### 手动触发发版(workflow_dispatch)

```
Actions → Release → Run workflow
  Use workflow from: main
  强制版本类型: 留空(自动推断)/ patch / minor / major
  → 绿按钮
```

适用场景:
- 自动触发的 paths 不命中,但确实想发(比如纯 RN 升级合并后)
- 想强制某个 bump 类型(自动推断给的不对,如 0.x 阶段想用 patch 而非 minor)
- CI 自动发版挂了,手动重试

### 关闭 / 跳过 Dependabot PR

- 单个 PR:评论 `@dependabot close` 或 UI 点 Close
- 永久 ignore 某依赖某版本:`@dependabot ignore this <version|minor version|major version|dependency>`
- 全局 ignore 规则(`.github/dependabot.yaml` 加 ignore 块):

```yaml
ignore:
  - dependency-name: '*'
    update-types: ['version-update:semver-major']   # 完全停掉所有 major
```

### 手动升级依赖(绕过 Dependabot)

适用 yarn 4 lockfile 解析有坑 / 想精确控制升级 / major 跨版本需手测:

```sh
git switch -c chore/manual-upgrade-<pkg>
yarn up "<pkg>@<version>"                    # 升单个
yarn up "react-native@0.85.3" "@react-native/*@0.85.3"   # 批量同前缀
yarn install
yarn lint && yarn typecheck && yarn test
# 手测后 push + PR
```

### 回滚版本

不推荐(npm 不能 unpublish 已发布超过 72h 的版本),但可:

- **deprecate** 某版本:`npm deprecate @unif/react-native-design@0.2.0 "包含 bug,请升 0.2.1"`(消费者 install 会看到 warning)
- **发新 patch 修问题**:`feat:` 改回去 / `fix:` 紧急修补,正常流水线发版

### 本地 branch 清理

GitHub Auto-delete head branches **只删远端**,本地的 stale branch 要自己清理:

```sh
# 1. 同步远端删除状态(把本地的 origin/<branch> remote-tracking ref 清掉)
git fetch --prune

# 2. 看哪些本地 branch 已经 "orphan"(upstream 在远端被删)
git branch -vv | grep ': gone\]'

# 3. 一行批量删 orphan 本地 branch
git fetch --prune && git branch -vv | awk '/: gone]/{print $1}' | xargs -r git branch -D
```

写成 alias 一劳永逸(`~/.gitconfig`):
```ini
[alias]
  prune-local = "!git fetch --prune && git branch -vv | awk '/: gone]/{print $1}' | xargs -r git branch -D"
```

之后 `git prune-local` 一键清理。建议每周跑一次 / 切回 main 后跑一次。

**为什么用 `-D` 强删**:squash merge 后本地 branch 的 commit hash 跟 main 上的 squashed commit **不是** ancestor 关系,`git branch -d`(小写)会拒绝删,认为"未合并"。`-D` 配合 `:gone]` 过滤是标准做法,安全。

---


---

[← 索引](../AUTOMATION.md) · [← Org 级共享基础设施](./09-org-sharing.md) · [排查常见报错 →](./11-troubleshooting.md)
