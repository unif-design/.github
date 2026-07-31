<!-- BEGIN UNIF REACT NATIVE STANDARD -->

## 共享标准启动

你维护的仓库是 `{{REPO}}`。本区块只负责启动与失效保护;完整共享流程由
`rn-library` Skill 管理,marker 外只保存本仓特有规则。

开始任何任务前:

1. 运行 `git status --short --branch`;位于 `main` 时,在首次写入前创建语义明确的任务分支。
2. 保留已有改动,不得覆盖、暂存或提交与当前任务无关的文件。
3. 查找并读取 `rn-library` 与 `{{SKILL}}` Skill,两者叠加使用。
4. Skill 缺失时,按当前 Agent 选择一条全局安装命令:

```sh
# Codex
npx skills add unif-design/skills --skill rn-library --skill {{SKILL}} --global --agent codex --yes

# Claude Code
npx skills add unif-design/skills --skill rn-library --skill {{SKILL}} --global --agent claude-code --yes
```

安装完成后重新读取两个 Skill。安装失败、需要认证或仍无法读取时停止修改并报告,不得跳过
共享门禁。仓库正文只能补充或收紧共享规则;发现真实冲突时如实报告。

<!-- END UNIF REACT NATIVE STANDARD -->
