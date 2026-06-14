# AI Team

AI Team 是一个本地优先的 Flutter 桌面应用，用聊天方式驱动多模型协同开发团队。用户可以配置 OpenAI 兼容模型、角色提示词、团队成员和本地项目工作区，由默认秘书成员在团队会话中分配任务、汇总成员输出，并通过受控补丁流程修改本地文件。

## 当前能力

- 飞书式三栏工作台：左侧会话和团队列表，中间聊天流，右侧成员状态、命令请求、补丁和审计日志。
- OpenAI 兼容模型配置：`baseUrl`、`apiKey`、`modelName`、流式开关、温度和最大 Token。
- 角色配置：身份、目标、约束、输出格式、命令白名单、命令黑名单、目录限制和命令确认策略。
- 团队配置：成员名称、角色、模型和默认秘书成员。
- 团队会话：用户向团队发任务后，秘书协调非秘书成员响应并生成汇总。
- 成员私聊：每个成员都有独立会话，输出与团队会话分离保存。
- 本地项目：选择工作区后可浏览安全相对路径、读取文件、生成 diff 补丁，并且必须经用户确认后才应用。
- 命令审批：角色命令策略先评估命令，允许的命令也可要求用户确认，执行结果进入审计日志。
- 本地持久化：应用状态保存在本机，API Key 通过 secret store 抽象保存，普通 JSON 状态默认不写入密钥。
- 配置导入导出：导出密钥需要显式选择包含密钥，导入失败时保留当前状态。

## 数据边界

应用不依赖后端服务。默认数据文件位于用户主目录下的应用数据目录，密钥不进入常规配置 JSON。导出配置时，只有用户显式选择包含密钥，才会把 API Key 写入导出文件。

本地项目写入采用补丁确认模式。模型和成员不能直接改文件，应用会先生成 unified diff，用户确认后才写入目标工作区文件。

## 开发环境

项目使用 Flutter 桌面端，当前主要验证 macOS。

```sh
/Users/swcrbt/develop/flutter/bin/flutter --version
/Users/swcrbt/develop/flutter/bin/flutter pub get
```

运行桌面应用：

```sh
/Users/swcrbt/develop/flutter/bin/flutter run -d macos
```

构建 debug 包：

```sh
/Users/swcrbt/develop/flutter/bin/flutter build macos --debug
```

## 验证命令

每个实现阶段提交前至少运行：

```sh
/Users/swcrbt/develop/flutter/bin/flutter test
/Users/swcrbt/develop/flutter/bin/flutter analyze
/Users/swcrbt/develop/flutter/bin/flutter build macos --debug
```

文档或注释类变更仍应确认工作区只包含预期文件，并在提交信息的 `Tested:` / `Not-tested:` trailer 中说明验证范围。

## Git 提交约定

每个阶段独立提交。提交信息遵循 Lore 协议：

```text
<intent line: why the change was made>

Constraint: <external constraint>
Rejected: <alternative> | <reason>
Confidence: <low|medium|high>
Scope-risk: <narrow|moderate|broad>
Directive: <future warning>
Tested: <verified commands>
Not-tested: <known gaps>
```

## MVP 验收清单

- 无后端依赖，数据保留本地。
- 可以配置多个 OpenAI 兼容模型。
- 可以配置角色提示词和权限。
- 可以创建团队和成员，并为成员选择角色与模型。
- 默认秘书能在团队会话中自动分配任务。
- 成员消息能在团队会话和成员私聊中查看。
- 本地项目修改必须经过 diff 确认。
- 配置可导入导出，密钥导出必须显式确认。

