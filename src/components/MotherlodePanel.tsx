import { useState } from 'react';
import { invoke } from '@tauri-apps/api/core';

interface Props {
  readings: Array<[[number, number], number]>;
  location: [number, number] | null;
}

export default function MotherlodePanel({ readings, location }: Props) {
  const [pos, setPos] = useState({ x: '', y: '', dist: '' });

  const addManual = () => {
    invoke('add_motherlode_reading', {
      x: parseFloat(pos.x),
      y: parseFloat(pos.y),
      distance: parseFloat(pos.dist),
    });
    setPos({ x: '', y: '', dist: '' });
  };

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h3 style={{ margin: 0 }}>Motherlode ({readings?.length ?? 0}/3)</h3>
        <button onClick={() => invoke('clear_motherlode')}>Reset</button>
      </div>

      {location && (
        <p style={{ color: '#FF44FF', fontWeight: 'bold' }}>
          Found at: ({Math.round(location[0])}, {Math.round(location[1])})
        </p>
      )}

      {(readings?.length ?? 0) < 3 && !location && (
        <p style={{ color: '#888', fontSize: 13 }}>
          Use the motherlode survey from 3 different positions.
        </p>
      )}

      <details style={{ marginTop: 8 }}>
        <summary style={{ cursor: 'pointer', fontSize: 13 }}>Add reading manually</summary>
        <div style={{ display: 'flex', gap: 4, marginTop: 6 }}>
          <input placeholder="X" value={pos.x} onChange={e => setPos(p => ({ ...p, x: e.target.value }))} style={{ width: 55 }} />
          <input placeholder="Y" value={pos.y} onChange={e => setPos(p => ({ ...p, y: e.target.value }))} style={{ width: 55 }} />
          <input placeholder="Dist" value={pos.dist} onChange={e => setPos(p => ({ ...p, dist: e.target.value }))} style={{ width: 55 }} />
          <button onClick={addManual}>Add</button>
        </div>
      </details>
    </div>
  );
}
