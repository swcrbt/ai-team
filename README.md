# AI Team

AI Team 是一个本地优先的 Flutter 桌面应用，用 Codex-like 的聊天工作台组织多模型协作团队。用户可以配置 OpenAI 兼容模型、角色、成员、团队和项目安全策略，通过群聊或私聊驱动成员完成分析、命令审批、diff 审阅和审计留痕。

## 当前能力

- Codex-like 工作台：64px 深色图标侧边栏，入口顺序为消息、团队、模型、角色、成员、项目、审计和设置。
- 消息体验：消息栏只展示群聊和私聊，聊天区采用顶部 header、中间消息流、底部固定 composer。
- 输入区：发送按钮固定在右下角，token 圆形进度位于发送按钮左侧，弹层展示上下文、输入、输出和缓存命中。
- 模型管理：按模型列表维护 provider、模型名、Base URL、上下文窗口、流式开关、温度和最大 Token。
- 角色管理：按角色列表维护职责、提示词、命令策略和项目读取/补丁权限。
- 成员管理：按成员列表维护角色与模型绑定，并可从成员行打开私聊。
- 团队管理：用卡片管理开发团队、测试团队等团队对象，编辑成员组合与协作模式，并从团队发起群聊。
- 项目管理：集中展示项目列表、边界状态、命令审批和补丁确认。
- 命令审批：命令请求以独立消息状态呈现，待审批可允许或拒绝，已允许可执行、停止或查看日志。
- Diff 审阅：补丁以文件 tab、增删统计和展开视图呈现，用户确认后才应用。
- 审计日志：按最新优先展示命令、补丁、模型诊断和配置变更记录，支持过滤和详情查看。
- 设置中心：管理持久化存储目录、导入导出和应用级配置。

## 数据边界

应用不依赖后端服务。普通状态、会话、审计和缓存使用应用内配置的持久化目录；API Key 通过 secret store 抽象保存，默认不会写入普通 JSON 配置。导出配置时，只有用户显式选择包含密钥，才会把 API Key 写入导出文件。

项目写入采用补丁确认模式。模型和成员不能直接改文件，应用会先生成 unified diff，用户确认后才写入目标项目文件。

思考内容只展示模型 provider 返回的 reasoning/thinking 字段，不生成或转述隐藏推理。

## 开发环境

项目使用 Flutter 桌面端，当前主要验证 macOS。

架构边界见 [docs/architecture.md](docs/architecture.md)。旧的公共导入 `app.dart`、`core/domain.dart`、`core/orchestrator.dart` 和 `core/model_gateway.dart` 保持兼容；新增代码优先使用更聚焦的 `application`、`ui`、`core/workspace`、`core/commands`、`core/orchestration` 和 `core/model` 模块。

准备依赖：

```sh
flutter --version
flutter pub get
```

运行桌面应用：

```sh
flutter run -d macos
```

构建 debug 包：

```sh
flutter build macos --debug
```

## 验证命令

实现类改动提交前至少运行：

```sh
flutter test
flutter analyze
flutter build macos --debug
```

如果改动影响聊天滚动、composer 或会话切换，再运行：

```sh
flutter test integration_test/chat_scroll_position_e2e_test.dart -d macos
```

文档或注释类变更可只运行：

```sh
git diff --check
```

## Git 提交约定

任务只有在相关改动完成验证并提交到 git 后才算完成。不要把未提交的工作区变更报告为已完成；如果确实不能提交，必须明确说明阻塞原因和未提交文件。

每个阶段独立提交。提交信息应说明意图、约束、验证命令和未覆盖风险。

## MVP 验收清单

- 可以配置多个 OpenAI 兼容模型。
- 可以配置角色提示词和权限。
- 可以创建团队和成员，并为成员选择角色与模型。
- 消息栏只展示群聊和私聊。
- 聊天 composer 固定在底部。
- 默认秘书能在团队会话中分配任务并汇总结果。
- 成员消息能在团队会话和成员私聊中查看。
- 命令执行必须经过策略和审批链路。
- 项目修改必须经过 diff 确认。
- 配置可导入导出，密钥导出必须显式确认。
