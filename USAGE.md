# Gorgon Survey - Usage Guide

Gorgon Survey is a browser-based game companion that overlays survey markers on a shared screen capture of the game. It watches the game's chat log to detect surveys automatically and lets you visually track their locations on the map and in your inventory.

## Getting Started

1. Start the application (see README or CLAUDE.md for dev server instructions).
2. Open your browser and navigate to `http://localhost:4000`.
3. Go to the **Settings** tab in the sidebar and enter the path to your game's log folder in the **Log Folder** field. Click **Save & Watch** to start monitoring the chat log for survey events.

## Screen Sharing

1. Click the **Share Screen** button in the main area.
2. Your browser will prompt you to select a screen or window to share. Choose your game window.
3. The game video feed will appear in the main area with a transparent canvas overlay on top for drawing markers.

## Setting Zones

Zones define rectangular regions on the shared screen that the app uses for detection and inventory tracking. Each zone is defined by clicking two corners.

### Map Zone (Detect Zone)

The map zone tells the app where the in-game map is on screen, so it can auto-detect survey marker positions.

1. In the **Surveys** tab, click **Set Map Zone**.
2. The cursor changes to a crosshair. Click once to set the first corner of the rectangle.
3. Click again to set the opposite corner. A yellow dashed rectangle labeled "Detect Zone" appears over the selected area.
4. To remove the zone, click **Clear Map Zone**.

### Inventory Zone

The inventory zone defines where your in-game inventory is on screen, so you can tag inventory items with survey numbers.

1. In the **Surveys** tab, click **Set Inv Zone**.
2. Click twice (two corners) to define the rectangle, same as the map zone. A teal dashed rectangle labeled "Inventory Zone" appears.
3. To remove the zone, click **Clear Inv Zone**.

## Survey Detection

Surveys are detected automatically by parsing the game's chat log. When the LogWatcher detects a new survey event in the log file, it appears in the sidebar survey list with its survey number, name, and offset coordinates (dx, dy).

No manual action is needed for detection -- just make sure the log folder is configured in Settings.

## Manual Marker Placement

When **Auto-place on survey** is turned off (the default), each newly detected survey needs to be placed on the map manually:

1. A prompt reading "Click on the map to place survey" appears at the top of the main area.
2. The cursor changes to a crosshair. Click on the map where the survey marker should go.
3. A numbered blue circle appears at that position, and the placement prompt disappears.

You can also reposition a marker at any time using the crosshair button in the sidebar (see Managing Surveys below).

## Auto-Place on Survey

When enabled, the app automatically captures a frame from the screen and scans it for red circle markers whenever a new survey is detected in the log. It then places the survey marker at the detected position.

1. Go to the **Settings** tab.
2. Click the **Auto-place on survey** toggle button to turn it ON.
3. When a new survey appears in the chat log, the app waits 500ms (to let the game UI settle), captures the map zone, and runs circle detection to place the marker automatically.

This setting is persisted across sessions.

## Inventory Marking

Inventory markers let you tag items in your inventory with the corresponding survey numbers so you can keep track of which survey sample is which.

1. First, set up an **Inventory Zone** (see Setting Zones above).
2. A hint "Click inventory items to mark them" appears in the sidebar.
3. Click on items inside the inventory zone. Each click places a small numbered circle. The numbers are assigned sequentially based on the current survey list.
4. To undo the last placed inventory marker, click **Undo Mark (N)** in the sidebar, where N is the current marker count.

When a survey is marked as collected, its corresponding inventory marker is automatically removed and the remaining markers shift positions to fill the gap.

## Managing Surveys (Sidebar)

The **Surveys** tab in the sidebar lists all detected surveys. Each survey entry shows its number, name, and offset. The following actions are available:

- **Done / Undo** -- Toggle a survey's collected status. Collected surveys appear with a green marker on the map (instead of blue) and are styled differently in the sidebar list. The route path only connects uncollected surveys.
- **Crosshair button** -- Replace the marker position. Clears the current position and prompts you to click a new location on the map.
- **X button** -- Delete the survey entirely, removing it from the list and the map.
- **Clear All** -- Remove all surveys and all inventory markers at once.
- **Lock Surveys / Unlock Surveys** -- When locked, new surveys detected from the chat log will not be added to the list. Existing surveys continue to update normally. Useful when you want to stop tracking new surveys temporarily.

## Right-Click Actions

Right-clicking on the canvas overlay provides quick actions for markers:

- **Right-click a survey marker on the map** -- Toggles its collected status (same as clicking Done/Undo in the sidebar).
- **Right-click an inventory marker** -- Removes that inventory marker. The remaining markers shift positions to fill the gap, preserving their survey number assignments.

## Settings Tab

The Settings tab contains two configuration options:

- **Log Folder** -- The path to the game's log directory. Enter the path and click **Save & Watch** to start (or restart) the log file watcher.
- **Auto-place on survey** -- Toggle button that enables or disables automatic marker placement when a new survey is detected. When ON, the app captures a frame and uses image detection to place the marker. When OFF, you place markers manually by clicking on the map.

## Visual Reference

- **Blue circles** -- Uncollected survey markers on the map, labeled with survey numbers.
- **Green circles** -- Collected survey markers on the map.
- **White dashed lines** -- Route path connecting uncollected markers in an optimized order (nearest-neighbor).
- **Yellow dashed rectangle** -- Map detection zone.
- **Teal dashed rectangle** -- Inventory zone.
- **Small blue circles in inventory zone** -- Inventory markers with survey numbers.
- **Crosshair cursor** -- Indicates you are placing a marker or setting a zone corner.
