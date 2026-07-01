# Architecture Recovery Audit

This document records the recovery pass after the initial architecture refactor.
It exists because commit history alone is not enough evidence that the goal-mode
refactor is complete.

## Baseline

- Branch: `codex/team-chat-collaboration`
- Existing refactor commits reviewed: `e2607d4` through `a40d7fe`
- Baseline verification:
  - `/Users/swcrbt/develop/flutter/bin/flutter analyze` passed
  - `/Users/swcrbt/develop/flutter/bin/flutter test` passed with 222 tests
  - `git diff --check` passed

## Confirmed Improvements

- Major `part` aggregation has been replaced by real Dart library imports and
  compatibility facades.
- Core domain, model gateway, orchestration, application, and UI folders now
  have explicit public barrels and focused implementation files.
- `AppController` already delegates persistence queue, streaming drafts,
  conversation sessions, and workspace/command operations.
- UI management pages and chat widgets are split into focused modules.

## Remaining Blockers

These are not behavior regressions, but they still block calling the architecture
refactor complete under the no-downgrade goal.

- `lib/application/app_controller.dart` is still too broad. It mixes facade API,
  configuration validation, task queue mutation, conversation lifecycle,
  dispatch lifecycle, title generation, cancellation, and state lookup helpers.
- `lib/core/orchestration/team_orchestrator.dart` still combines high-level team
  workflow with secretary summary, assignment recovery, member dispatch, and
  command continuation details.
- `lib/ui/dialogs/config_dialogs.dart` is still an omnibus dialog module for
  team, model, role, member, workspace, command, export, and helper concerns.
- `test/core/domain/domain_test.dart` no longer mirrors the split production
  domain modules and makes JSON compatibility failures hard to isolate.
- `test/ui/app_widget_test.dart` covers many unrelated UI workflows in one file,
  including chat rendering, scroll behavior, dialogs, management pages,
  composer shortcuts, and orchestration UI.

## Recovery Decision

The next stories must continue the refactor instead of accepting these as
residual risks. The target is not smaller code for its own sake; each split must
make ownership, dependency direction, or test failure locality clearer while
preserving persisted state, model behavior, command behavior, patch behavior,
and UI workflows.
