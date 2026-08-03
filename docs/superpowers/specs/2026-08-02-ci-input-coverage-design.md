# React Native CI 输入覆盖设计

## 背景

共享 `ci.yml` 使用 `dorny/paths-filter` 跳过不受影响的 job。当前过滤器只列出
`example/package.json` 与 `example/ios/**`,会让 `example/src/**`、
`example/android/**`、example 配置文件以及 Yarn 运行时文件的变更漏过相关门禁。

## 目标

1. 任意 `example/**` 变更都运行 lint、test、library build、Android build 与 iOS build。
2. `.yarnrc.yml` 或 `.yarn/releases/**` 变更运行全部代码门禁和 website 门禁。
3. 用可执行的 glob 匹配契约测试锁定代表性输入,不只检查模板中是否出现某行文本。
4. 修复先进入 `.github` 任务分支与 PR;合并后再同步四个 React Native 仓库。

## 方案

采用正确性优先的保守过滤:

- `shared` 与 `code` 都加入 `example/**`、`.yarnrc.yml`、`.yarn/releases/**`。
- `website` 加入 `.yarnrc.yml`、`.yarn/releases/**`。
- 保留现有 `android` / `ios` 细分过滤器;`shared` 会让任意 example 集成输入同时触发
  两个平台,避免新增配置或目录时再次产生漏项。

不采用逐个枚举 example 文件的方案。它能少跑少量 CI,但每增加一个 Metro、Babel、
Gradle 或原生 fixture 都要同步维护过滤器,漂移风险高于节省的执行时间。

## 测试

扩展 `scripts/ci-template.test.sh`,实际解析模板中的 filters,把 glob 转成正则并断言:

- `example/src/App.tsx`、`example/android/app/build.gradle`、
  `example/babel.config.js` 同时命中 `shared` 与 `code`。
- `.yarnrc.yml`、`.yarn/releases/yarn-4.11.0.cjs` 同时命中
  `shared`、`code` 与 `website`。

先观察测试在旧模板上失败,再修改模板使其通过。随后运行 Bash 语法、ShellCheck、
actionlint 与共享仓全部契约测试。

## 同步与安全边界

- 四仓只同步 `.github/workflows/ci.yml`;仓库特有 release workflow 不在本修复范围。
- Design 与 HMS 保留当前任务分支和其他会话改动。
- Umeng 从 `origin/main` 建纯 CI 分支,不把另一会话的 release 规格提交带入 CI PR。
- 不手工发版;合并后的 release 交给各仓自动流程。
