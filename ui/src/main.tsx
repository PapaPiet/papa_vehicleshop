import React from 'react';
import { createRoot } from 'react-dom/client';
import './lib/theme.css';
import { ToastProvider } from './components/ui';
import { DealerApp } from './app/DealerApp';

const params = new URLSearchParams(window.location.search);
if (params.get('papa_phone') === '1') {
  document.documentElement.classList.add('papa-phone');
}

createRoot(document.getElementById('root')!).render(
  <ToastProvider>
    <DealerApp />
  </ToastProvider>,
);
