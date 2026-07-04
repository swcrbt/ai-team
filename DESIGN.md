# Design

## Source of truth
- Status: Active
- Last refreshed: 2026-07-04
- Primary product surfaces: group chat command center, member private chat, team/model/role/member/project/audit/settings pages, project safety and patch review, command approval, sidebar icon system.
- Evidence reviewed: `README.md`, `docs/architecture.md`, `lib/ui/app_shell.dart`, `lib/ui/sidebar.dart`, `lib/ui/conversation_sidebar.dart`, `lib/ui/chat/chat_pane.dart`, `lib/ui/chat/chat_controls.dart`, `lib/ui/management/config_management_pages.dart`, `lib/ui/management/chat_status_cards.dart`, `lib/ui/management/audit_log_page.dart`, `lib/ui/management/settings_page.dart`.
- Figma reference: https://www.figma.com/design/b661TshWPrgj83XFpvk04D
- Figma revision status: Legacy external reference; current active mockup is the repo-local Open Design artifact.
- Open Design artifact: `docs/design/open-design/ai-team-codex-ui-redesign/index.html`
- Open Design desktop source: import the artifact folder directly from this repository; do not maintain a copied namespace version.

## Brand
- Personality: quiet, dense, operational, Codex-like, and local-first.
- Trust signals: explicit command approval, visible diff confirmation, audit trail, model/request diagnostics, and clear local data boundaries.
- Avoid: landing-page composition, decorative gradients, large marketing cards, fake reasoning, and UI text that explains features instead of supporting work.

## Product goals
- Goals: help a user coordinate model-backed team work, keep group chat and private chat visually distinct, keep chat input anchored at the bottom with the send action in the composer lower-right corner, approve sensitive commands, review patches, and inspect audit history without losing context.
- Non-goals: social chat polish, consumer onboarding, autonomous file writes, or hiding safety state behind settings.
- Success signals: the active conversation, member state, pending command, proposed patch, and audit trail are visible from the relevant work surface.

## Personas and jobs
- Primary personas: local developer/operator, team-orchestration power user, and reviewer of model-generated file changes.
- User jobs: configure messages/teams/models/roles/members/projects/audit/settings from sidebar entries, start team or member chats, monitor serial/parallel collaboration, approve commands, apply/reject diffs, and inspect audit details.
- Key contexts of use: desktop Flutter app, repeated long sessions, mixed Chinese/English technical content, local repositories, and OpenAI-compatible model endpoints.

## Information architecture
- Primary navigation: compact dark icon rail for messages, teams, models, roles, members, project, audit, and settings. Each entry has a designed 20px linear icon with default, hover, active, and disabled states.
- Core routes/screens: Group Chat Command Center, Member Private Chat, Team Management, Model Management, Role Management, Member Management, Project Safety and Patch Review, Audit Console, App Settings, Sidebar Icon System.
- Content hierarchy: active work first, safety confirmation second, historical/audit evidence third. The message sidebar is only for group/private conversations; model and project objects remain sidebar destinations, not conversation rows. Team, model, role, and member management are separate sidebar pages in that order, not sections inside one settings page, and each management page presents its object list before item editing.

## Design principles
- Principle 1: keep command, patch, member, and audit state close to the action that created it, but do not keep a right-side safety panel permanently resident in chat.
- Principle 2: prefer dense, scannable panels with stable dimensions over decorative containers.
- Tradeoffs: a contextual safety drawer preserves message width and should appear only when a command, patch, or audit action needs attention; full project safety remains a separate sidebar page.

## Visual language
- Color: neutral app surface, white panels, near-black command rail and code blocks, blue primary action, green success, amber waiting, red blocked.
- Typography: Inter for Figma mockups; Flutter implementation can map this to the app text theme. Roboto Mono is used for commands, paths, model fields, and diffs.
- Spacing/layout rhythm: 8px base rhythm, 12-16px panel padding, compact rows, fixed side rails.
- Shape/radius/elevation: 6-8px radius, 1px borders, minimal shadows.
- Motion: subtle state transitions only; no decorative motion.
- Imagery/iconography: functional custom linear icons only, with tooltip support in implementation. Sidebar icon meanings are messages, teams, models, roles, members, project, audit, and settings.

## Components
- Existing components to reuse: Flutter Material 3 widgets, existing sidebars, chat pane, split send button, shared dialog frame, management panels, and audit rows.
- New/changed components: fixed-bottom chat composer with lower-right send action, circular token meter placed inside the composer directly left of the send button, input/output/cache-hit token breakdown popover, returned-thinking panel inside messages, command approval state card, diff review card, list-first team/model/role/member management pages, team cards for examples such as 开发团队 and 测试团队 without lifecycle status chips, project management list inside the project safety surface, settings storage-directory configuration for state/audit/conversation/cache persistence, conversation status pills for pending approval and allowed-running states, on-demand safety drawer, safety-oriented project review panel, audit detail drawer, sidebar icon components, compact state pills, concrete page layouts for every sidebar entry.
- Variants and states: sidebar icon default/hover/active/disabled, command pending/approved/executed/denied/failed as separate system or assistant message variants rather than simultaneous state panels or user-authored execution bubbles, patch pending/applied/rejected, diff collapsed/expanded/applied, model streaming/stopped/failed, empty project.
- Token/component ownership: keep tokens local to `lib/ui` theme unless a broader design-system refactor is approved.

## Accessibility
- Target standard: keyboard-friendly desktop UI with readable contrast.
- Keyboard/focus behavior: preserve chat composer shortcuts, visible focus rings, and non-destructive escape/stop behavior.
- Contrast/readability: command/diff blocks must remain high contrast; status chips must not rely on color alone.
- Screen-reader semantics: command approvals, patch confirmations, and destructive actions need explicit labels.
- Reduced motion and sensory considerations: no required motion for comprehension.

## Responsive behavior
- Supported breakpoints/devices: desktop-first macOS; narrow desktop windows should collapse secondary panels before hiding primary chat.
- Layout adaptations: icon rail stays fixed, conversation sidebars can shrink or collapse, safety status opens as a temporary drawer, and the chat composer remains fixed to the bottom of the chat surface. Composer footer metadata is not shown; the token meter lives in the input surface immediately before the send button.
- Touch/hover differences: desktop hover affordances are allowed, but all actions need keyboard/click access.

## Interaction states
- Loading: streaming messages show real generation status and optional returned thinking/reasoning only when the provider response includes it.
- Empty: no project, no audit, and no command request states should provide one clear primary action.
- Error: model/command/project errors show source, recoverable action, and audit reference.
- Success: applied patches and executed commands enter audit immediately.
- Management: management pages are list-first. Teams use card-style team objects such as 开发团队, 测试团队, 文档团队, and 发布团队, with editing shown only for the selected card; team cards do not show enabled/draft/template status because those are not domain states. Model, role, member, and project pages use object lists as the primary surface, with selected-item editing as secondary detail. Group chat context is always shared and is not configurable per team.
- Disabled: blocked actions state why, especially missing project or secretary constraints.
- Offline/slow network: model request diagnostics and retry/stop states stay visible.
- Settings: persistent storage directories are first-class settings for state, audit logs, conversations, and cache. Directory changes should expose choose/open/clear actions and require migration confirmation before saving.

## Content voice
- Tone: concise, operational, and explicit.
- Terminology: use existing terms such as 团队, 成员, 角色, 模型, 项目, 命令请求, 补丁, Diff, 审计.
- Microcopy rules: do not invent model reasoning; label confirmations by consequence, not by generic warnings.

## Implementation constraints
- Framework/styling system: Flutter desktop, Material 3, current `ThemeData` and focused `lib/ui` modules.
- Design-token constraints: avoid introducing a separate token framework until implementation work starts.
- Performance constraints: chat scrolling and streaming must remain stable; avoid layout changes that resize message lists during streaming.
- Compatibility constraints: preserve current public facades and local-first data boundary.
- Test/screenshot expectations: implementation should add widget coverage for sidebar navigation/icons, group-vs-private chat presentation, returned-thinking panels, fixed-bottom composer behavior, approval states, and run `flutter test`, `flutter analyze`, and `flutter build macos --debug` before completion.

## Open questions
- [ ] Should Inter become an explicit app font, or should implementation keep Flutter platform defaults while matching spacing and hierarchy?
