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

## Remaining Blockers At Baseline

These were the blockers found during the recovery baseline audit. They were not
behavior regressions, but they blocked calling the architecture refactor complete
under the no-downgrade goal at that point in the recovery.

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

## Resolution Note

The baseline blockers were resolved by the recovery stories that followed this
audit:

- Application and orchestration coupling were reduced further in `9e87594` by
  extracting conversation/session, dispatch lifecycle, title generation, member
  chat dispatch, and secretary private dispatch components.
- Dialog, UI workflow, and domain compatibility test blockers were resolved by
  the focused UI/dialog and domain-test split commits recorded in
  `.omx/ultragoal/ledger.jsonl`.

## Post-Completion Goal Status Note

After the final checkpoint, `omx ultragoal status` reports `artifact goals:
complete` and `artifactComplete: true`. The raw microgoal count still includes
two historical states:

- `G001` remains `in_progress` because the original objective-mismatched story
  is preserved as audit history; it has `steeringStatus: superseded` and is
  replaced by completed `G009`.
- `G008` remains `review_blocked` because the first final review was
  intentionally recorded as a failed gate; completed `G010` is the blocker
  resolution story with the final `APPROVE` and `CLEAR` evidence.

`get_goal` returning no active Codex goal is expected after `update_goal` marks
the aggregate Codex goal complete. The final `G010` ledger entry contains the
completed Codex goal snapshot and quality-gate evidence.

## Stable Objective Rule

Codex goal mode and Ultragoal must not maintain competing goal text. The only
authoritative aggregate Codex objective for this recovery plan is the
`codexObjective` value in `.omx/ultragoal/goals.json`:

```text
Complete the durable AI Team architecture refactor recovery plan in .omx/ultragoal/goals.json, including blocker-resolution stories and final verification, under the original no-downgrade constraints; use .omx/ultragoal/ledger.jsonl as the audit trail.
```

Future recovery or follow-up work should create or reconcile Codex goal mode
from that exact pointer objective only. Story-level objectives, old aliases, and
newly enumerated checklists belong in `.omx/ultragoal/goals.json` and
`.omx/ultragoal/ledger.jsonl`; they must not replace the aggregate Codex
objective.
