# Multi-Session Support Design

## Goal

Allow multiple concurrent users (browser tabs) to use the app independently without interfering with each other. Each session gets its own LogWatcher, survey state, and inventory markers.

## Decisions

- **Session identity**: Auto-generated UUID per browser tab. No persistence across page reloads.
- **Isolation level**: Fully isolated — each session gets its own LogWatcher and AppState.
- **Config**: Global defaults with per-session in-memory overrides. Global config at `~/.config/gorgon-survey/settings.json`. Session overrides are ephemeral.
- **Cleanup**: 30s timeout after disconnect. Survives accidental refreshes. LogWatcher terminated after timeout.

## Architecture

### New Modules

**`GorgonSurvey.SessionManager`** (GenServer)
- Tracks active sessions: `session_id -> {watcher_pid, config_overrides}`
- Handles registration, deregistration, cleanup timers
- Provides `register/1`, `deregister/1`, `reconnect/1`, `start_watcher/2`, `get_config/2`, `put_config/3`
- On disconnect: starts 30s `Process.send_after` timer
- On reconnect: cancels timer, returns existing LogWatcher reference

**`GorgonSurvey.SessionSupervisor`** (DynamicSupervisor)
- Supervises per-session LogWatcher processes
- Children started/stopped by SessionManager

### Modified Modules

**`GorgonSurvey.LogWatcher`**
- No longer started globally
- Started per-session via DynamicSupervisor
- Registered via `Registry` with `{:session, session_id}` key
- PubSub topic scoped to `"game_state:#{session_id}"`

**`GorgonSurvey.ConfigStore`**
- Add `get/3` with optional session_id parameter
- Session overrides checked first via SessionManager, then fall back to global file

**`GorgonSurveyWeb.SurveyLive`**
- `mount/3` generates UUID, registers with SessionManager
- Subscribes to `"game_state:#{session_id}"`
- All LogWatcher calls use session-specific server reference
- `terminate/2` triggers SessionManager cleanup timer

**`GorgonSurvey.Application`**
- Remove global LogWatcher from supervision tree
- Add Registry, SessionManager, SessionSupervisor

### Supervision Tree

```
Application Supervisor (one_for_one)
+-- Telemetry
+-- DNSCluster (conditional)
+-- Phoenix.PubSub
+-- Registry (session_registry)
+-- SessionManager
+-- SessionSupervisor (DynamicSupervisor)
|   +-- LogWatcher (session-abc123)
|   +-- LogWatcher (session-def456)
|   +-- ...
+-- Endpoint
```

### Data Flow

```
mount -> generate UUID -> SessionManager.register(session_id)
  -> user sets log folder -> SessionManager.start_watcher(session_id, folder)
  -> DynamicSupervisor starts LogWatcher(session_id)
  -> LogWatcher broadcasts to "game_state:#{session_id}"
  -> only that session's LiveView receives updates

disconnect -> SessionManager.schedule_cleanup(session_id, 30s)
  -> reconnect within 30s -> cancel timer, reuse LogWatcher
  -> timeout -> DynamicSupervisor terminates LogWatcher
```
