# TODO

## Refactoring

- [ ] Extract `ResizeHandles` component, `HANDLES` constant, and `ResizeDirection` type into `src/components/ResizeHandles.tsx` (duplicated between Overlay.tsx and InventoryOverlay.tsx)
- [ ] Extract body/document style reset useEffect into a shared hook (e.g. `src/hooks/useOverlayBodyReset.ts`) — identical 6-line block in both overlays
- [ ] Extract window resize tracking into a shared hook (e.g. `src/hooks/useWindowSize.ts`) — identical useState + useEffect in both overlays
- [ ] Consider an `OverlayShell` layout component wrapping the outer div (outline, drag bar, resize handles) — accepts `label` prop for drag bar text

## Known Limitations

- [ ] `onStorage` listener in Overlay.tsx does not apply calibration migration logic (old `scale` → `scaleX`/`scaleY`)
- [ ] InventoryOverlay sorts by `route_order!` with non-null assertion on potentially null values
- [ ] Right-click skip on inventory overlay is not feasible while click-through is enabled (surveys must be skipped from map overlay or control panel)
- [ ] WebKitGTK ghosting: previous canvas frames bleed through on transparent windows during state transitions
