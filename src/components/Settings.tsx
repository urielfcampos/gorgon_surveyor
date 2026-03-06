import { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';

export default function Settings({ onClose }: { onClose: () => void }) {
  const [logFolder, setLogFolder] = useState('');
  const [status, setStatus] = useState('');

  useEffect(() => {
    invoke<any>('get_config').then((c: any) => setLogFolder(c.log_folder || ''));
  }, []);

  const save = async () => {
    try {
      await invoke('start_log_watching', { logFolder });
      setStatus('Watching log file!');
    } catch (e) {
      setStatus(`Error: ${e}`);
    }
  };

  return (
    <div style={{ padding: 16 }}>
      <h3>Settings</h3>
      <label style={{ fontSize: 13 }}>Chat Log Folder:</label>
      <input
        value={logFolder}
        onChange={e => setLogFolder(e.target.value)}
        style={{ width: '100%', marginTop: 4, boxSizing: 'border-box' }}
        placeholder="Path to ProjectGorgon folder..."
      />
      <p style={{ fontSize: 11, color: '#888', margin: '4px 0' }}>
        Proton example: ~/.steam/steam/steamapps/compatdata/APPID/pfx/drive_c/users/steamuser/AppData/Roaming/ProjectGorgon
      </p>
      {status && (
        <p style={{ color: status.startsWith('Error') ? 'red' : 'green', fontSize: 13 }}>{status}</p>
      )}
      <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
        <button onClick={save}>Save & Watch</button>
        <button onClick={onClose}>Close</button>
      </div>
    </div>
  );
}
