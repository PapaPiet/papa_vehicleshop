/**
 * Ladeanzeigen und Rueckmeldungen (Spezifikation "Ladeanzeigen, Rueckmeldungen, lokaler Cache", Abschnitt A).
 * Gleicher Code in papa_os_police, papa_os_justice und papa_os_mechanic; Farben kommen aus den
 * CSS-Variablen --pf-* der jeweiligen App (feedback.css).
 */
import React, { useEffect, useState } from 'react';
import { ArrowPathIcon, CheckCircleIcon, ExclamationTriangleIcon, InboxIcon, XMarkIcon } from '@heroicons/react/24/outline';
import {
  dismissToast,
  feedbackErrorText,
  getFeedbackState,
  getFeedbackTexts,
  subscribeFeedback,
  type FeedbackState,
} from './uiFeedback';
import './feedback.css';

export function useFeedbackState(): FeedbackState {
  const [s, setS] = useState<FeedbackState>(getFeedbackState());
  useEffect(() => subscribeFeedback(setS), []);
  return s;
}

/** Zentrierter Ladekreis (App-Start, Details). */
export function LoadingState(props: { label?: string; fill?: boolean; compact?: boolean }) {
  const texts = getFeedbackTexts();
  const label = props.label ?? texts.fbLoading;
  return (
    <div
      className={`pf-loading${props.fill ? ' pf-loading-fill' : ''}${props.compact ? ' pf-loading-compact' : ''}`}
      role="status"
      aria-live="polite"
      aria-busy="true"
    >
      <span className="pf-spinner" aria-hidden="true" />
      <span className="pf-loading-label">{label}</span>
    </div>
  );
}

/** Platzhalter fuer Listen, solange die erste Antwort fehlt. */
export function SkeletonList(props: { rows?: number; label?: string }) {
  const rows = Math.max(1, props.rows ?? 5);
  return (
    <div className="pf-skeleton-list" role="status" aria-busy="true" aria-label={props.label ?? getFeedbackTexts().fbLoading}>
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="pf-skeleton-row">
          <span className="pf-skeleton-line pf-skeleton-line-main" style={{ width: `${55 + ((i * 17) % 35)}%` }} />
          <span className="pf-skeleton-line pf-skeleton-line-sub" style={{ width: `${30 + ((i * 23) % 40)}%` }} />
        </div>
      ))}
    </div>
  );
}

/** Fehlerzustand mit verstaendlichem Text und "Erneut versuchen". */
export function ErrorState(props: { error?: unknown; message?: string; onRetry?: () => void; compact?: boolean }) {
  const texts = getFeedbackTexts();
  const text = props.message ?? feedbackErrorText(props.error, texts);
  return (
    <div className={`pf-error-state${props.compact ? ' pf-error-compact' : ''}`} role="alert">
      <ExclamationTriangleIcon className="pf-state-icon" aria-hidden="true" />
      <div className="pf-error-text">
        <strong>{texts.fbLoadFailed}</strong>
        <span>{text}</span>
      </div>
      {props.onRetry ? (
        <button type="button" className="pf-btn" onClick={props.onRetry}>
          <ArrowPathIcon className="pf-btn-icon" aria-hidden="true" />
          {texts.fbRetry}
        </button>
      ) : null}
    </div>
  );
}

/** Leerzustand statt leerer Liste. */
export function EmptyState(props: { label?: string; children?: React.ReactNode }) {
  return (
    <div className="pf-empty-state">
      <InboxIcon className="pf-state-icon" aria-hidden="true" />
      <span>{props.label ?? getFeedbackTexts().fbEmpty}</span>
      {props.children}
    </div>
  );
}

/**
 * Globale Ebene: Fortschrittsbalken (> 400 ms), Hinweis "Dauert laenger..." (> 8 s) und Toasts.
 * Einmal im App-Wurzelelement einhaengen.
 */
export function FeedbackLayer() {
  const s = useFeedbackState();
  const texts = getFeedbackTexts();
  return (
    <>
      <div className={`pf-progress${s.busy ? ' is-active' : ''}`} aria-hidden="true">
        <span />
      </div>
      <div className="pf-live" aria-live="polite" role="status">
        {s.slow ? (
          <div className="pf-slow-hint">
            <span className="pf-spinner pf-spinner-sm" aria-hidden="true" />
            {texts.fbSlow}
          </div>
        ) : null}
      </div>
      <div className="pf-toasts" aria-live="polite">
        {s.toasts.map((toast) => (
          <div key={toast.id} className={`pf-toast pf-toast-${toast.kind}`} role={toast.kind === 'error' ? 'alert' : 'status'}>
            {toast.kind === 'error' ? (
              <ExclamationTriangleIcon className="pf-toast-icon" aria-hidden="true" />
            ) : (
              <CheckCircleIcon className="pf-toast-icon" aria-hidden="true" />
            )}
            <span className="pf-toast-text">{toast.text}</span>
            {toast.retry ? (
              <button
                type="button"
                className="pf-toast-action"
                onClick={() => {
                  dismissToast(toast.id);
                  toast.retry?.();
                }}
              >
                {texts.fbRetry}
              </button>
            ) : null}
            <button type="button" className="pf-toast-close" aria-label={texts.fbDismiss} onClick={() => dismissToast(toast.id)}>
              <XMarkIcon aria-hidden="true" />
            </button>
          </div>
        ))}
      </div>
    </>
  );
}
