import { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';

export interface Survey {
  id: number;
  zone: string;
  x: number;
  y: number;
  collected: boolean;
  route_order: number | null;
}

export interface AppState {
  surveys: Survey[];
  motherlode_readings: Array<[[number, number], number]>;
  motherlode_location: [number, number] | null;
  player_position: [number, number] | null;
}

const EMPTY_STATE: AppState = {
  surveys: [],
  motherlode_readings: [],
  motherlode_location: null,
  player_position: null,
};

export function useSurveyState() {
  const [state, setState] = useState<AppState>(EMPTY_STATE);

  useEffect(() => {
    invoke<AppState>('get_state').then(setState).catch(console.error);

    const unlisten = listen<AppState>('state-updated', (event) => {
      setState(event.payload);
    });

    return () => {
      unlisten.then(f => f());
    };
  }, []);

  return state;
}
