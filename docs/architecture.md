# AI Team Architecture

AI Team is a local-first Flutter desktop app. The UI drives an application
controller, the controller coordinates state and persistence, and core services
own model orchestration, workspace access, command execution, patching, and
local storage.

## Dependency Direction

- `lib/ui/` depends on `lib/application/` and `lib/core/`.
- `lib/application/` owns UI-facing app coordination and depends on core
  services.
- `lib/core/orchestration/` owns team and member model workflows.
- `lib/core/workspace/` owns workspace path safety, file listing, file reads,
  and patch proposal creation.
- `lib/core/commands/` owns command runners and command execution result
  mapping.
- `lib/core/domain/` owns persisted app data types and JSON compatibility.
- `lib/core/model/` owns OpenAI-compatible request and response handling.

Core modules must not import Flutter UI code. UI code should not duplicate
workspace or command safety rules; it should call the shared core services.

## Compatibility Boundary

The current public imports remain valid during the staged refactor:

- `package:ai_team/app.dart`
- `package:ai_team/core/domain.dart`
- `package:ai_team/core/orchestrator.dart`
- `package:ai_team/core/model_gateway.dart`

New code should prefer the focused modules, but compatibility facades stay in
place until tests and callers have been migrated deliberately.
