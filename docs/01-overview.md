[← 索引](../AUTOMATION.md) · [日常开发主流程 →](./02-daily-workflow.md)

---

# Unif Design 自动化流程标准

`unif-design` 组织所有仓库共享的 CI / 发版 / 依赖管理 / PR review 标准。**以 `@unif/react-native-design` 仓库为参考实例**,其他 repo 套用同一套模式(配置文件路径、命令、ruleset 勾选项一致;只有 npm 包名 / specific scripts 名等需要替换)。

各 repo 在自己的 README / CONTRIBUTING 里加链接 `https://github.com/unif-design/.github/blob/main/AUTOMATION.md` 指过来即可,**不需要每个 repo 复制一份**。

---

## 总览

```
开 feature branch
       │
       │ 改代码 + 本地 verify
       ▼
   git commit (conventional commits)
       │
       │ git push -u origin <branch>
       ▼
   GitHub UI 开 PR(PR template 自动套)
       │
       │ CI 自动跑 5 个 check
       ▼
   ┌─────────────────┐
   │ Branch protection│  阻止直接 push main
   │   - PR 必须     │  阻止合并未通过 CI
   │   - CI 必须绿   │
   └────────┬────────┘
            │ Squash and merge
            ▼
          main
            │
            │ 命中 release.yml paths?
            ▼
   ┌─────────────────────────────────┐
   │ Release workflow(自动 / 手动)  │
   │   1. 跑 lint + typecheck + test │
   │   2. release-it --ci            │
   │      └ 推断 bump 类型           │
   │      └ npm Trusted Publishing   │
   │      └ git commit + tag         │
   │      └ 创建 GitHub Release      │
   │      └ 写 CHANGELOG.md          │
   └─────────────────────────────────┘
            │
            ▼
       npm registry + GitHub Release
```

---


---

[← 索引](../AUTOMATION.md) · [日常开发主流程 →](./02-daily-workflow.md)
