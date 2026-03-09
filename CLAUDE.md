# CLAUDE.md

## Tool Management

All commands must be prefixed with `mise exec --`. Tools (Elixir, Erlang, Node) are managed via `.mise.toml`.

## Commands

```bash
# Install dependencies
mise exec -- mix deps.get

# Dev server (hot-reload)
mise exec -- mix phx.server

# Interactive console
mise exec -- iex -S mix phx.server

# Run all tests
mise exec -- mix test

# Run specific test file
mise exec -- mix test test/gorgon_survey/log_parser_test.exs

# Compile check
mise exec -- mix compile --warnings-as-errors
```

## Architecture

Phoenix LiveView app running locally as a game companion. Single page at `/`.

### Data Flow

```
chat.log → LogWatcher GenServer → PubSub → LiveView → JS Hook → canvas
```

### Key Modules

| Module | Responsibility |
|---|---|
| `GorgonSurvey.LogParser` | Regex parsing of chat log lines into events |
| `GorgonSurvey.AppState` | Pure state struct with survey/motherlode management |
| `GorgonSurvey.LogWatcher` | GenServer tailing log file, maintains state, broadcasts via PubSub |
| `GorgonSurvey.ConfigStore` | JSON config persistence at `~/.config/gorgon-survey/settings.json` |
| `GorgonSurveyWeb.SurveyLive` | LiveView page — sidebar + screen capture area |
| `ScreenCapture` (JS Hook) | Browser getDisplayMedia, canvas overlay, click-to-place |

### Frontend

- Screen capture via `getDisplayMedia` API
- Canvas overlay for survey markers drawn over mirrored video
- Click to place surveys, right-click to toggle collected
- State pushed from server via LiveView `push_event`
