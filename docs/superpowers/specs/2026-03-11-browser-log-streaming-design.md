# Browser Log Streaming Design

## Problem

The LogWatcher currently reads `chat.log` directly from the server's filesystem via FileSystem (inotify). This only works when the server runs on the same machine as the game. For remote/deployed use, the log file needs to come from the user's browser.

## Solution

Add a second input mode to LogWatcher: browser-based log streaming using the File System Access API. The user picks their `chat.log` file via the browser file picker, JS polls for new content, and sends delta lines to the server over the existing LiveView WebSocket.

Both modes coexist — local file tailing for self-hosted, browser streaming for remote.

## Architecture

### Dual-Mode LogWatcher

The existing LogWatcher GenServer gains a `mode` field:

- **`:local`** (default) — Current behavior. FileSystem inotify watches the log file directory, reads new lines from file offset. No changes needed.
- **`:remote`** — No FileSystem watcher, no file handle. Receives lines via a new `ingest_lines/2` cast. Parses and broadcasts identically to local mode.

### New Client: LogStreamer JS Hook

A new JS hook (`LogStreamer`) separate from ScreenCapture:

1. User clicks "Select Log File" button → `window.showOpenFilePicker()` → stores `FileSystemFileHandle`
2. Starts a polling loop (~1s interval via `setInterval`)
3. Each tick: `handle.getFile()` → check `file.size` against stored offset → if larger, `file.slice(offset).text()` → send new lines via `pushEvent("log_lines", { lines: "..." })`
4. Updates stored offset to `file.size`
5. Sends status events for UI feedback (streaming/error/stopped)

### SessionManager Changes

- New `start_remote_watcher/1` — starts LogWatcher in `:remote` mode (no log folder needed)
- Existing `start_watcher/2` unchanged for local mode

### SurveyLive Changes

- New `"start_log_stream"` event handler — calls `SessionManager.start_remote_watcher/1`, assigns watcher
- New `"log_lines"` event handler — forwards lines to `LogWatcher.ingest_lines/2`
- New `"stop_log_stream"` event handler — stops the remote watcher
- New `log_mode` assign (`:none`, `:local`, `:remote`) for UI state

### UI Changes (Settings Tab)

Replace the single "Log Folder" form with two options:

```
Log Watcher
  ┌─────────────────────────────────┐
  │ ○ Local File   ○ Stream from    │
  │   (self-hosted)  Browser        │
  ├─────────────────────────────────┤
  │ [Local mode: folder input]      │
  │ -- OR --                        │
  │ [Stream mode: file picker btn]  │
  │ [Status: Streaming ● / Idle ○]  │
  └─────────────────────────────────┘
```

### Data Flow (Remote Mode)

```
chat.log (user's PC)
  → File System Access API (browser polls ~1s)
  → LogStreamer JS Hook (extracts delta lines)
  → pushEvent("log_lines") over WebSocket
  → SurveyLive handles event
  → LogWatcher.ingest_lines(watcher, lines) (GenServer.cast)
  → LogParser → AppState update → PubSub broadcast
  → SurveyLive → push_event to JS
```

## Browser Compatibility

File System Access API (`showOpenFilePicker`) is supported in Chrome 86+, Edge 86+, Opera 72+. Not supported in Firefox or Safari. The UI should show browser compatibility info and gracefully hide the stream option in unsupported browsers.

## Error Handling

- **File permission revoked**: JS catches `NotAllowedError`, shows status, stops polling
- **File deleted/moved**: `getFile()` throws, catch and show error status
- **WebSocket disconnect**: LiveView reconnect handles this — LogStreamer re-sends from last known offset on reconnect
- **Unsupported browser**: Hide "Stream from Browser" option, show only local mode
