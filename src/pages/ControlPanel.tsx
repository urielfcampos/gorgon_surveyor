import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useSurveyState } from "../hooks/useSurveyState";
import SurveyList from "../components/SurveyList";
import MotherlodePanel from "../components/MotherlodePanel";
import Settings from "../components/Settings";
import { CALIBRATION_KEY } from "../constants";

type Mode = "survey" | "motherlode";

export default function ControlPanel() {
  const state = useSurveyState();
  const [mode, setMode] = useState<Mode>("survey");
  const [showSettings, setShowSettings] = useState(false);
  const [overlayVisible, setOverlayVisible] = useState(true);
  const [zones, setZones] = useState<string[]>([]);
  const [zone, setZone] = useState("Serbule");
  const [invOverlayVisible, setInvOverlayVisible] = useState(true);
  const [invColumns, setInvColumns] = useState(
    () => localStorage.getItem("gorgon-inv-columns") ?? "11",
  );
  const [invStartSlot, setInvStartSlot] = useState(
    () => localStorage.getItem("gorgon-inv-start-slot") ?? "1",
  );

  useEffect(() => {
    invoke<string[]>("get_zones").then(setZones);
    invoke<any>("get_config").then((c: any) => {
      if (c.current_zone) setZone(c.current_zone);
    });
  }, []);

  const recalibrate = () => {
    localStorage.removeItem(CALIBRATION_KEY);
  };

  const toggleOverlay = async () => {
    try {
      const visible = await invoke<boolean>("toggle_overlay_visible");
      setOverlayVisible(visible);
    } catch (e) {
      console.error(e);
    }
  };

  const toggleInvOverlay = async () => {
    try {
      const visible = await invoke<boolean>("toggle_inventory_overlay_visible");
      setInvOverlayVisible(visible);
    } catch (e) {
      console.error(e);
    }
  };

  const applyInvConfig = () => {
    const cols = parseInt(invColumns, 10);
    const slot = parseInt(invStartSlot, 10);
    if (!isNaN(cols) && cols > 0)
      localStorage.setItem("gorgon-inv-columns", String(cols));
    if (!isNaN(slot) && slot > 0)
      localStorage.setItem("gorgon-inv-start-slot", String(slot));
  };

  const recalibrateInv = () => {
    localStorage.removeItem("gorgon-inv-calibration");
  };

  const onZoneChange = async (z: string) => {
    setZone(z);
    try {
      const c = await invoke<any>("get_config");
      await invoke("save_config", { newConfig: { ...c, current_zone: z } });
    } catch (e) {
      console.error("Failed to save zone change:", e);
    }
  };

  return (
    <div style={{ padding: 16, fontFamily: "sans-serif", maxWidth: 400 }}>
      {showSettings ? (
        <Settings onClose={() => setShowSettings(false)} />
      ) : (
        <>
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
              marginBottom: 12,
            }}
          >
            <h2 style={{ margin: 0, fontSize: 18 }}>Gorgon Survey</h2>
            <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
              <select
                value={zone}
                onChange={(e) => onZoneChange(e.target.value)}
              >
                {zones.map((z) => (
                  <option key={z}>{z}</option>
                ))}
              </select>
              <button
                onClick={toggleOverlay}
                title={overlayVisible ? "Hide overlay" : "Show overlay"}
              >
                {overlayVisible ? "Hide" : "Show"}
              </button>
              <button onClick={() => setShowSettings(true)}>&#9881;</button>
            </div>
          </div>

          <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
            <button
              onClick={() => setMode("survey")}
              style={{
                flex: 1,
                fontWeight: mode === "survey" ? "bold" : "normal",
              }}
            >
              Regular Survey
            </button>
            <button
              onClick={() => setMode("motherlode")}
              style={{
                flex: 1,
                fontWeight: mode === "motherlode" ? "bold" : "normal",
              }}
            >
              Motherlode
            </button>
          </div>

          <div style={{ marginBottom: 8 }}>
            <button
              onClick={recalibrate}
              style={{ fontSize: 12, padding: "2px 8px" }}
            >
              Recalibrate Overlay
            </button>
          </div>

          <hr style={{ margin: "0 0 12px" }} />

          {mode === "survey" ? (
            <SurveyList surveys={state.surveys} />
          ) : (
            <MotherlodePanel
              readings={state.motherlode_readings}
              location={state.motherlode_location}
            />
          )}

          <hr style={{ margin: '12px 0 8px' }} />
          <h4 style={{ margin: '0 0 8px', fontSize: 14 }}>Inventory Overlay</h4>
          <div style={{ display: 'flex', gap: 4, alignItems: 'center', marginBottom: 6, fontSize: 12 }}>
            <span style={{ color: '#888' }}>Cols:</span>
            <input value={invColumns} onChange={e => setInvColumns(e.target.value)}
              style={{ width: 35, padding: '2px 4px', fontSize: 12 }} />
            <span style={{ color: '#888' }}>Start slot:</span>
            <input value={invStartSlot} onChange={e => setInvStartSlot(e.target.value)}
              style={{ width: 35, padding: '2px 4px', fontSize: 12 }} />
            <button onClick={applyInvConfig} style={{ fontSize: 12, padding: '2px 8px' }}>Set</button>
          </div>
          <div style={{ display: 'flex', gap: 4, fontSize: 12 }}>
            <button onClick={toggleInvOverlay}>{invOverlayVisible ? 'Hide' : 'Show'} Inv Overlay</button>
            <button onClick={recalibrateInv}>Recalibrate Inv</button>
          </div>
        </>
      )}
    </div>
  );
}
