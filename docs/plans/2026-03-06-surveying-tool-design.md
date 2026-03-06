# Gorgon Survey Tool — Design Document

**Date:** 2026-03-06
**Status:** Approved

## Overview

A cross-platform desktop companion app for the Project Gorgon surveying skill. The tool reads the game's chat logs to detect survey locations and motherlode distances, then displays an overlay on top of the game map with an optimized collection route.

**Inspired by:** [PgSurveyor-Disclosed](https://github.com/dlebansais/PgSurveyor-Disclosed)

---

## Tech Stack

| Layer | Technology |
|---|---|
| Desktop shell | Tauri 2.x |
| Backend logic | Rust |
| Frontend UI | React + TypeScript |
| Config persistence | TOML file via `serde` |
| File watching | `notify` crate |

**Platform target:** Cross-platform (Linux primary, with Windows support). Player runs the game under Wine/Proton on Linux.

---

## Architecture

### Two-Window Design

**1. Overlay Window**
- Properties: `transparent: true`, `decorations: false`, `always_on_top: true`, `setIgnoreCursorEvents(true)`
- Renders a transparent canvas over the game's minimap/map window
- Shows survey dots, route waypoints, and motherlode triangulation circles

**2. Control Panel Window**
- Normal Tauri window
- Handles zone selection, log path config, survey list, motherlode readings, and settings

### Data Flow

```
Game log file
     ↓
log_watcher (notify crate - tails file for new lines)
     ↓
log_parser (regex/pattern matching → structured events)
     ↓
App state (survey list, motherlode readings)
     ↓              ↓
path_optimizer   triangulator
     ↓              ↓
Overlay canvas  Control panel
```

### Rust Backend Modules

| Module | Responsibility |
|---|---|
| `log_watcher` | Watches the chat log file for new content using `notify` |
| `log_parser` | Parses chat lines to extract survey coordinates, motherlode distances, and collection events |
| `path_optimizer` | Nearest-neighbor TSP heuristic for route ordering |
| `triangulator` | Circle intersection math for motherlode location |
| `config` | Load/save settings (TOML) — log path, overlay calibration, zone |

---

## Overlay & Map Calibration

### Calibration Flow
1. User clicks "Calibrate Overlay" in the control panel
2. The overlay window briefly becomes visible with a colored drag handle / border
3. User positions it to align with the game's map window
4. The offset and size are saved to config

### Zone Maps
- Each supported zone has an embedded PNG top-down map image
- Each zone has a known real-world coordinate bounding box (to be determined from game data / wiki)
- Survey coordinates from the log are mapped: `game_coord → pixel_position` via linear scaling

### Overlay Rendering (transparent canvas)
- Red filled circles — uncollected survey locations
- Green filled circles — collected surveys
- Yellow numbered waypoints — ordered collection route
- Yellow lines — connecting the route
- Semi-transparent circles — motherlode distance readings
- Filled red dot — triangulated motherlode position

---

## Chat Log Parsing

### Log File Location (Wine/Proton)

Default path:
```
~/.steam/steam/steamapps/compatdata/<APPID>/pfx/drive_c/users/steamuser/AppData/Roaming/ProjectGorgon/
```

The user can override this path in Settings.

### Parsed Message Types

| Event | Pattern (to be validated against real logs) |
|---|---|
| Survey placed | Zone name + coordinates output when right-clicking a survey map |
| Motherlode distance | Distance in meters output after clicking a motherlode survey |
| Survey collected | Confirmation message when player collects a survey node |

> Note: Exact message formats must be validated against real game logs. The implementation will include a log debug viewer in settings.

---

## Path Optimization

**Algorithm:** Nearest-Neighbor TSP heuristic

1. Start at player's current position (or user-chosen start)
2. Visit the nearest unvisited survey node
3. Repeat until all nodes are visited
4. Return the ordered list

**Performance:** Runs in <1ms for typical survey counts (5–30 nodes). No external crate needed.

---

## Motherlode Triangulation

**Algorithm:** Circle intersection (3 readings)

1. Reading 1: circle centered at player position P1, radius = distance D1
2. Reading 2: circle centered at P2, radius = D2 → intersect with circle 1 → 0, 1, or 2 candidate points
3. Reading 3: circle centered at P3, radius = D3 → selects the correct candidate
4. Triangulated point displayed on overlay as a red dot, with the 3 distance circles shown semi-transparently

**Pure Rust math** — no geometry library needed.

---

## Control Panel UI

```
┌─ Gorgon Survey Tool ──────────────────────────────────┐
│  Zone: [Serbule ▾]        Status: Watching log...      │
│  ─────────────────────────────────────────────────     │
│  [Regular Survey Mode]  [Motherlode Mode]               │
│  ─────────────────────────────────────────────────     │
│  Surveys (5):                                           │
│    1. (123, 456) - Active                               │
│    2. (234, 567) - Next                                 │
│    3. (345, 678) - Pending  [Skip]                      │
│    ...                                                  │
│  [Clear All]  [Optimize Route]                          │
│  ─────────────────────────────────────────────────     │
│  Motherlode:                                            │
│    Reading 1: (pos) dist 340m                           │
│    Reading 2: (pos) dist 210m                           │
│    Reading 3: waiting...   [Add Manually]               │
│  ─────────────────────────────────────────────────     │
│  [⚙ Settings]  [Calibrate Overlay]                      │
└───────────────────────────────────────────────────────┘
```

### Settings Panel
- Log file path (with Wine prefix auto-detection helper)
- Overlay window opacity
- Dot sizes and colors
- Zone coordinate bounds (advanced)

---

## Configuration File

Stored at the OS config directory (e.g., `~/.config/gorgon-survey/settings.toml`):

```toml
log_path = "/path/to/ProjectGorgon/chat.log"
current_zone = "Serbule"

[overlay]
x = 100
y = 200
width = 400
height = 400
opacity = 0.8

[colors]
uncollected = "#FF4444"
collected = "#44FF44"
waypoint = "#FFFF00"
motherlode = "#FF00FF"
```

---

## Supported Zones (initial set)

Priority zones based on surveying prevalence:
- Serbule
- Eltibule
- Kur Mountains
- (Additional zones to be added based on coordinate data availability)

---

## Out of Scope (v1)

- Auto-detection of node exhaustion in Povus/Vidaria (manual skip only)
- Fullscreen game support (overlay requires windowed mode)
- Network packet inspection (100% log-based, no client modification)
- Automatic Wine prefix path detection (manual config only in v1)
