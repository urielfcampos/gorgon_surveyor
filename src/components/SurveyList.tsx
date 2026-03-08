import { invoke } from '@tauri-apps/api/core';
import { Survey } from '../hooks/useSurveyState';

export default function SurveyList({ surveys, locked }: { surveys: Survey[]; locked: boolean }) {
  const active = surveys
    .filter(s => !s.collected)
    .sort((a, b) => (a.route_order ?? 999) - (b.route_order ?? 999));

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h3 style={{ margin: 0 }}>Surveys ({active.length})</h3>
        <div style={{ display: 'flex', gap: 4 }}>
          <button
            onClick={() => invoke('toggle_surveys_locked')}
            style={{ fontSize: 12, background: locked ? '#cc4444' : undefined }}
          >
            {locked ? 'Locked' : 'Lock'}
          </button>
          <button onClick={() => invoke('clear_surveys')}>Clear All</button>
        </div>
      </div>
      {active.length === 0 && <p style={{ color: '#888', fontSize: 13 }}>No surveys detected yet</p>}
      <ul style={{ listStyle: 'none', padding: 0, margin: '8px 0' }}>
        {active.map(s => (
          <li key={s.id} style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0', borderBottom: '1px solid #eee' }}>
            <span>
              <b style={{ color: '#FFAA00' }}>#{s.survey_number}</b>{' '}
              <span style={{ color: '#888', fontSize: 11 }}>path:{s.route_order}</span>{' '}
              ({Math.round(s.x)}, {Math.round(s.y)})
            </span>
            <button onClick={() => invoke('skip_survey', { id: s.id })} style={{ fontSize: 12 }}>Skip</button>
          </li>
        ))}
      </ul>
    </div>
  );
}
