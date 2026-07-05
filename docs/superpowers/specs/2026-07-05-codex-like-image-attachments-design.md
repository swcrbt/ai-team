# Codex 级图片粘贴、提交与预览设计

## 背景

当前项目已经有图片附件雏形：聊天输入支持选择、拖入和剪贴板图片；消息模型能持久化 `MessageAttachment`；OpenAI 与 Anthropic 请求能把本地图片转成 data URL 或 base64 image block；消息气泡也有图片网格和弹窗预览。

参考项目 Codex 的强项不是图片缩略图，而是完整可靠的附件链路：剪贴板图片读取、粘贴路径识别、附件状态管理、模型图片能力校验、失败恢复、队列和历史保真。Flutter GUI 应保留真实缩略图预览，同时达到 Codex 的可靠性。

## 目标

- 支持从文件选择、拖入、剪贴板图片、粘贴图片路径添加图片。
- 支持识别 `file://`、引号路径、shell escaped 路径、Windows 路径、WSL 风格路径和普通本地路径中的图片。
- 待发送区展示真实缩略图、编号、删除入口、错误状态和无障碍标签。
- 提交前校验当前模型是否支持图片；不支持时阻止提交并保留文本和图片草稿。
- 图片保存、读取、编码或模型请求失败时给出明确反馈，不静默丢图。
- 队列任务、会话历史、失败恢复和应用重启后都能保留图片附件语义。
- 删除会话时清理该会话拥有的图片文件。
- 用测试覆盖 Codex 同等级关键链路。

## 非目标

- 不实现远程图片 URL 输入的完整 UI；本次聚焦本地图片和剪贴板来源。数据模型保留扩展空间。
- 不照搬 Codex 的 TUI `[Image #N]` 文本占位交互；Flutter 使用缩略图和附件列表。
- 不在本次重做聊天整体布局、模型管理页面或非图片文件附件。

## 设计原则

- 结构化附件是事实来源，文本中不插入也不解析 `[Image #N]`。
- 显式图片粘贴失败要可见；普通文本粘贴路径识别失败则退回普通文本，不打断用户输入。
- UI 入口校验和提交层校验都要存在，避免模型切换或状态延迟导致错误提交。
- 提交失败不能损坏用户草稿；用户应能换模型、删图或重试。
- 临时文件和持久文件的所有权明确，只有应用创建且未提交的临时文件可自动删除。

## 架构

### 附件草稿层

新增 `PendingImageAttachment` 与 `PendingImageAttachmentController`，由 `ChatPaneState` 持有。

`PendingImageAttachment` 字段：
- `id`：草稿期稳定 ID。
- `source`：`pickedFile`、`droppedFile`、`clipboardImage`、`pastedPath`。
- `file`：当前可读文件。
- `ownedTemporaryFile`：是否由应用创建且需要取消/销毁时删除。
- `mimeType`、`fileSize`、`width`、`height`。
- `status`：`ready`、`invalid`、`failed`。
- `errorMessage`：用于 UI 提示和测试断言。

Controller 负责：
- 从 `File`、`XFile`、剪贴板 bytes、粘贴文本创建草稿附件。
- 校验 MIME、扩展名、图片解码和文件可读性。
- 去重同一路径或同一剪贴板临时文件。
- 维护顺序和编号。
- 删除单张、清空所有、提交成功后释放临时文件所有权、提交失败后保持草稿。

### 粘贴服务

新增 `ImagePasteService`，把 Codex 的两类粘贴能力拆开：

- `readClipboardImages()`：读取系统剪贴板里的 PNG、JPEG、GIF、WebP 数据，写入应用临时文件，再交给草稿 controller。
- `parsePastedImagePath(String text)`：识别单一路径输入，包括 `file://`、单双引号、shell escaped、Windows drive path、UNC path 和普通本地路径。路径存在且可解码为图片时添加附件；否则让 TextField 按普通文本粘贴。

Flutter 桌面不需要 Codex 的终端 paste burst 状态机，因为系统 paste 事件由 TextField 和键盘事件提供；但保留“图片粘贴”和“文本路径粘贴”两条路径的分层。

### 持久图片服务

扩展 `ImageService`：
- 保存图片时接收最终 `messageId`，保证附件 ID、文件名和消息 ID 一致。
- 支持从草稿附件保存到 `images/<conversationId>/`。
- 图片保存失败返回结构化错误，不静默跳过。
- `readImageAsDataUrl` 失败时抛出可展示错误，由 gateway 或 dispatch 层转成用户可见消息。
- 会话删除时调用 `cleanupConversationImages(conversationId)`。

### 模型能力

给 `ModelProfile` 增加 `supportsImages`，默认值为 `true`，避免老配置被硬阻塞。模型管理 UI 提供“支持图片输入”开关。后续如需扩展，可迁移为 `inputModalities`。

提交前检查当前会话实际使用的模型：
- 成员私聊检查该成员模型。
- 团队会话检查秘书模型；如果后续图片会传给工作成员，再扩展为参与成员全量检查。
- 不支持图片时不调用 dispatch，保留文本和附件并显示错误。

dispatch 层再次校验，作为 UI 外调用和状态变化的安全网。

### 队列和历史

`QueuedTask` 增加 `attachments: List<MessageAttachment>` 字段。排队、暂停、恢复和运行时都保留附件。

`ChatMessage.attachments` 继续作为已提交消息的事实来源。失败恢复时保留草稿层 `PendingImageAttachment`；成功提交后只持久化 `MessageAttachment`。

跨会话历史菜单继续显示文本预览；如果首条消息只有图片，预览显示“图片 N 张”。

## UI 行为

### 待发送区

- 输入框上方显示横向缩略图条。
- 每张图片显示编号、删除按钮、错误图标或加载状态。
- 点击缩略图打开预览对话框，可左右切换、放大缩小、关闭。
- 删除按钮使用 `IconButton`/`Semantics`，提供明确 label。
- 不使用解释性教学文案；错误只在实际失败时显示简短提示。

### 粘贴体验

- `Cmd/Ctrl+V` 时先尝试读取剪贴板图片；如果读到图片，消费本次粘贴事件并添加附件；如果没有图片，放行 TextField 原生文本粘贴。
- 文本粘贴前检查剪贴板文本；如果文本是单一图片路径，则消费本次粘贴事件并添加附件；如果不是图片路径，则放行原生文本粘贴。
- 显式图片粘贴失败显示 snackbar 或输入区错误状态。

### 提交体验

- 文本和图片都为空时不提交。
- 图片存在但模型不支持时，阻止提交并保留草稿。
- 图片保存失败时，保留草稿并显示具体图片的错误状态。
- 模型请求失败时，已提交到会话的用户消息保留附件；如果失败发生在提交前，则草稿保留。

### 已发送消息

- 用户消息和模型消息均可显示图片附件网格。
- 单图使用较大的预览，多图使用稳定尺寸网格，移动或窄宽时不溢出。
- 图片缺失或损坏时显示稳定占位，不破坏消息布局。

## 数据流

1. 用户选择、拖入或粘贴图片。
2. `ImagePasteService` 或 picker/drop handler 产出文件或 bytes。
3. `PendingImageAttachmentController` 校验并加入草稿。
4. UI 渲染缩略图列表。
5. 用户提交。
6. UI 与 dispatch 层检查模型图片能力。
7. dispatch 创建最终用户消息 ID。
8. `ImageService` 把草稿图片保存为 `MessageAttachment`。
9. orchestrator 将带附件的 `ChatMessage` 写入会话并发给模型。
10. gateway 读取附件 data URL，构造 OpenAI 或 Anthropic 图片请求。
11. 成功后清理草稿临时文件所有权；失败按发生阶段恢复或保留状态。

## 错误处理

- 剪贴板不可用：显示“剪贴板不可用”。
- 剪贴板无图片：不报错，让普通粘贴继续。
- 路径不是图片：不报错，作为文本粘贴。
- 图片不可读或解码失败：附件进入错误状态，不允许提交该附件。
- 模型不支持图片：阻止提交，保留草稿。
- 保存图片失败：阻止提交，保留草稿并标记失败图片。
- 请求编码图片失败：模型调用失败消息中说明图片读取失败，避免静默丢图。

## 测试策略

### 单元测试

- `ImagePasteService` 路径解析：`file://`、单双引号、shell escaped、空格路径、Windows drive path、UNC path、非图片文本。
- `PendingImageAttachmentController`：添加、去重、删除、临时文件清理、错误状态。
- `ImageService`：保存图片、尺寸读取、data URL、保存失败。
- `ModelProfile` 序列化默认 `supportsImages=true`。

### 应用层测试

- 支持图片的模型能提交文本加图片。
- 不支持图片的模型阻止提交并保留草稿。
- 队列任务保留图片附件。
- 删除会话清理图片目录。
- gateway 图片读取失败不静默跳过。

### Widget 测试

- 待发送缩略图显示编号、删除、错误态。
- 图片路径粘贴转换为附件，普通文本粘贴保留文本。
- 已发送消息 local-only、text+local、多图、缺失图片占位。
- 窄宽布局不溢出，按钮有语义 label。

## 迁移

- 现有 `ChatMessage.attachments` JSON 保持兼容。
- 现有 `ModelProfile` 缺少 `supportsImages` 时按 `true` 读取。
- 现有已保存图片目录继续可读。
- 新队列附件字段缺失时按空列表读取。

## 验收标准

- 在 macOS 桌面可直接复制截图或图片文件后粘贴为待发送图片。
- 粘贴本地图片路径或 `file://` 图片路径会添加附件；粘贴普通文本不受影响。
- 图片模型能收到 OpenAI/Anthropic 请求中的图片 content part。
- 非图片模型阻止提交并保留输入。
- 保存或读取图片失败时用户能看到错误，且图片不会被静默丢弃。
- 排队、暂停恢复和删除会话的图片行为都有测试覆盖。
