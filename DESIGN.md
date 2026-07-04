# Design

## Source of truth
- Status: Draft
- Last refreshed: 2026-07-04
- Primary product surfaces: chat command center, team/model/role/member/project/audit/settings entries, project workspace and patch review, command approval, sidebar icon system.
- Evidence reviewed: `README.md`, `docs/architecture.md`, `lib/ui/app_shell.dart`, `lib/ui/sidebar.dart`, `lib/ui/conversation_sidebar.dart`, `lib/ui/chat/chat_pane.dart`, `lib/ui/chat/chat_controls.dart`, `lib/ui/management/config_management_pages.dart`, `lib/ui/management/chat_status_cards.dart`, `lib/ui/management/audit_log_page.dart`, `lib/ui/management/history_page.dart`.
- Figma reference: https://www.figma.com/design/b661TshWPrgj83XFpvk04D
- Figma revision status: Pending canvas sync; Figma MCP returned a Starter plan tool-call limit on 2026-07-04 before this revision could be applied to the file.
- Open Design artifact: `docs/design/open-design/ai-team-codex-ui-redesign/index.html`
- Open Design desktop source: import the artifact folder directly from this repository; do not maintain a copied namespace version.

## Brand
- Personality: quiet, dense, operational, Codex-like, and local-first.
- Trust signals: explicit command approval, visible diff confirmation, audit trail, model/request diagnostics, and clear local data boundaries.
- Avoid: landing-page composition, decorative gradients, large marketing cards, fake reasoning, and UI text that explains features instead of supporting work.

## Product goals
- Goals: help a user coordinate model-backed team work, keep chat input anchored at the bottom, approve sensitive commands, review patches, and inspect audit history without losing context.
- Non-goals: social chat polish, consumer onboarding, autonomous file writes, or hiding safety state behind settings.
- Success signals: the active conversation, member state, pending command, proposed patch, and audit trail are visible from the relevant work surface.

## Personas and jobs
- Primary personas: local developer/operator, team-orchestration power user, and reviewer of model-generated file changes.
- User jobs: configure models/roles/members/projects/settings from sidebar entries, start team or member chats, monitor serial/parallel collaboration, approve commands, apply/reject diffs, and inspect audit details.
- Key contexts of use: desktop Flutter app, repeated long sessions, mixed Chinese/English technical content, local repositories, and OpenAI-compatible model endpoints.

## Information architecture
- Primary navigation: compact dark icon rail for messages, teams, models, roles, members, project, audit, and settings. Each entry has a designed 20px linear icon with default, hover, active, and disabled states.
- Core routes/screens: Chat Command Center, Team Setup and Routing, Project Safety and Patch Review, Settings Audit Console, Sidebar Icon System.
- Content hierarchy: active work first, safety confirmation second, historical/audit evidence third.

## Design principles
- Principle 1: keep command, patch, member, and audit state close to the action that created it.
- Principle 2: prefer dense, scannable panels with stable dimensions over decorative containers.
- Tradeoffs: a right-side context/audit inspector adds density but reduces message width; keep it fixed and collapsible if implementation needs smaller windows.

## Visual language
- Color: neutral app surface, white panels, near-black command rail and code blocks, blue primary action, green success, amber waiting, red blocked.
- Typography: Inter for Figma mockups; Flutter implementation can map this to the app text theme. Roboto Mono is used for commands, paths, model fields, and diffs.
- Spacing/layout rhythm: 8px base rhythm, 12-16px panel padding, compact rows, fixed side rails.
- Shape/radius/elevation: 6-8px radius, 1px borders, minimal shadows.
- Motion: subtle state transitions only; no decorative motion.
- Imagery/iconography: functional custom linear icons only, with tooltip support in implementation. Sidebar icon meanings are messages, teams, models, roles, members, project, audit, and settings.

## Components
- Existing components to reuse: Flutter Material 3 widgets, existing sidebars, chat pane, split send button, shared dialog frame, management panels, and audit rows.
- New/changed components: fixed-bottom chat composer, right-side conversation context inspector, safety-oriented project review panel, audit detail drawer, sidebar icon components, compact state pills.
- Variants and states: sidebar icon default/hover/active/disabled, command pending/approved/executed/denied/failed, patch pending/applied/rejected, model streaming/stopped/failed, empty workspace.
- Token/component ownership: keep tokens local to `lib/ui` theme unless a broader design-system refactor is approved.

## Accessibility
- Target standard: keyboard-friendly desktop UI with readable contrast.
- Keyboard/focus behavior: preserve chat composer shortcuts, visible focus rings, and non-destructive escape/stop behavior.
- Contrast/readability: command/diff blocks must remain high contrast; status chips must not rely on color alone.
- Screen-reader semantics: command approvals, patch confirmations, and destructive actions need explicit labels.
- Reduced motion and sensory considerations: no required motion for comprehension.

## Responsive behavior
- Supported breakpoints/devices: desktop-first macOS; narrow desktop windows should collapse secondary inspectors before hiding primary chat.
- Layout adaptations: icon rail stays fixed, conversation sidebars can shrink or collapse, right inspector becomes a drawer below constrained widths, and the chat composer remains fixed to the bottom of the chat surface.
- Touch/hover differences: desktop hover affordances are allowed, but all actions need keyboard/click access.

## Interaction states
- Loading: streaming messages show real generation status and optional returned reasoning.
- Empty: no workspace, no audit, and no command request states should provide one clear primary action.
- Error: model/command/workspace errors show source, recoverable action, and audit reference.
- Success: applied patches and executed commands enter audit immediately.
- Disabled: blocked actions state why, especially missing workspace or secretary constraints.
- Offline/slow network: model request diagnostics and retry/stop states stay visible.

## Content voice
- Tone: concise, operational, and explicit.
- Terminology: use existing terms such as 团队, 成员, 角色, 模型, 工作区, 命令请求, 补丁, 审计.
- Microcopy rules: do not invent model reasoning; label confirmations by consequence, not by generic warnings.

## Implementation constraints
- Framework/styling system: Flutter desktop, Material 3, current `ThemeData` and focused `lib/ui` modules.
- Design-token constraints: avoid introducing a separate token framework until implementation work starts.
- Performance constraints: chat scrolling and streaming must remain stable; avoid layout changes that resize message lists during streaming.
- Compatibility constraints: preserve current public facades and local-first data boundary.
- Test/screenshot expectations: implementation should add widget coverage for sidebar navigation/icons, fixed-bottom composer behavior, approval states, and run `flutter test`, `flutter analyze`, and `flutter build macos --debug` before completion.

## Open questions
- [ ] Should Inter become an explicit app font, or should implementation keep Flutter platform defaults while matching spacing and hierarchy?
- [ ] Should the custom sidebar icons ship as local vector assets, custom painters, or a mapped Material Icons implementation?
