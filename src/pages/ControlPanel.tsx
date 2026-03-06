import { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { useSurveyState } from '../hooks/useSurveyState';
import SurveyList from '../components/SurveyList';
import MotherlodePanel from '../components/MotherlodePanel';
import Settings from '../components/Settings';

type Mode = 'survey' | 'motherlode';

export default function ControlPanel() {
  const state = useSurveyState();
  const [mode, setMode] = useState<Mode>('survey');
  const [showSettings, setShowSettings] = useState(false);
  const [zones, setZones] = useState<string[]>([]);
  const [zone, setZone] = useState('Serbule');

  useEffect(() => {
    invoke<string[]>('get_zones').then(setZones);
    invoke<any>('get_config').then((c: any) => {
      if (c.current_zone) setZone(c.current_zone);
    });
  }, []);

  const onZoneChange = async (z: string) => {
    setZone(z);
    try {
      const c = await invoke<any>('get_config');
      await invoke('save_config', { newConfig: { ...c, current_zone: z } });
    } catch (e) {
      console.error('Failed to save zone change:', e);
    }
  };

  return (
    <div style={{ padding: 16, fontFamily: 'sans-serif', maxWidth: 400 }}>
      {showSettings ? (
        <Settings onClose={() => setShowSettings(false)} />
      ) : (
        <>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
            <h2 style={{ margin: 0, fontSize: 18 }}>Gorgon Survey</h2>
            <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              <select value={zone} onChange={e => onZoneChange(e.target.value)}>
                {zones.map(z => <option key={z}>{z}</option>)}
              </select>
              <button onClick={() => setShowSettings(true)}>&#9881;</button>
            </div>
          </div>

          <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
            <button
              onClick={() => setMode('survey')}
              style={{ flex: 1, fontWeight: mode === 'survey' ? 'bold' : 'normal' }}
            >
              Regular Survey
            </button>
            <button
              onClick={() => setMode('motherlode')}
              style={{ flex: 1, fontWeight: mode === 'motherlode' ? 'bold' : 'normal' }}
            >
              Motherlode
            </button>
          </div>

          <hr style={{ margin: '0 0 12px' }} />

          {mode === 'survey'
            ? <SurveyList surveys={state.surveys} />
            : <MotherlodePanel readings={state.motherlode_readings} location={state.motherlode_location} />
          }

          <hr style={{ margin: '12px 0 8px' }} />
          <button onClick={() => setShowSettings(true)} style={{ fontSize: 12 }}>&#9881; Settings</button>
        </>
      )}
    </div>
  );
}
