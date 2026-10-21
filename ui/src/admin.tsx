import React from 'react';
import { createRoot } from 'react-dom/client';
import './lib/theme.css';
import { ToastProvider } from './components/ui';
import { AdminApp } from './admin/AdminApp';

// Tell the Papa OS admin shell that the panel is ready (it answers with theme and context).
window.parent?.postMessage({ type: 'papa_os_admin', action: 'ready' }, '*');

createRoot(document.getElementById('root')!).render(
  <ToastProvider>
    <AdminApp />
  </ToastProvider>,
);
