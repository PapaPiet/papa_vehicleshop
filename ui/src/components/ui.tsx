import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import {
  CheckCircleIcon,
  ExclamationCircleIcon,
  InformationCircleIcon,
  XMarkIcon,
  InboxIcon,
  ArrowPathIcon,
} from '@heroicons/react/24/outline';
import { SkeletonList } from '../shared/FeedbackUi';
import { getFeedbackTexts } from '../shared/uiFeedback';
import { hasText, t } from '../lib/i18n';

// Toasts ---------------------------------------------------------------------------

type ToastKind = 'ok' | 'error' | 'info';
interface ToastItem { id: number; kind: ToastKind; text: string; retry?: () => void }
/** retry: optionaler Button "Erneut versuchen" (z. B. nach einem fehlgeschlagenen Speichern). */
type PushToast = (kind: ToastKind, text: string, retry?: () => void) => void;
const ToastCtx = createContext<PushToast>(() => undefined);

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([]);
  const nextId = useRef(1);
  const push = useCallback<PushToast>((kind, text, retry) => {
    const id = nextId.current++;
    setItems((prev) => [...prev.slice(-3), { id, kind, text, retry }]);
    window.setTimeout(() => setItems((prev) => prev.filter((x) => x.id !== id)), kind === 'error' ? (retry ? 8000 : 5200) : 3200);
  }, []);
  return (
    <ToastCtx.Provider value={push}>
      {children}
      <div className="toasts" role="status" aria-live="polite">
        {items.map((it) => {
          const Icon = it.kind === 'ok' ? CheckCircleIcon : it.kind === 'error' ? ExclamationCircleIcon : InformationCircleIcon;
          return (
            <div key={it.id} className={`toast ${it.kind}`} role={it.kind === 'error' ? 'alert' : undefined}>
              <Icon />
              <span>{it.text}</span>
              {it.retry && (
                <button
                  type="button"
                  className="toast-action"
                  onClick={() => {
                    setItems((prev) => prev.filter((x) => x.id !== it.id));
                    it.retry?.();
                  }}
                >
                  {t('fb_retry')}
                </button>
              )}
            </div>
          );
        })}
      </div>
    </ToastCtx.Provider>
  );
}

export function useToast() {
  return useContext(ToastCtx);
}

// Modal ----------------------------------------------------------------------------

export function Modal(props: {
  title: React.ReactNode;
  onClose: () => void;
  children: React.ReactNode;
  footer?: React.ReactNode;
  size?: 'narrow' | 'wide';
  icon?: React.ReactNode;
}) {
  const { onClose } = props;
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className={`modal ${props.size || ''}`} role="dialog" aria-modal="true">
        <div className="modal-head">
          {props.icon}
          <div className="h2">{props.title}</div>
          <button className="icon-btn" onClick={onClose} aria-label={t('ui_close')}>
            <XMarkIcon />
          </button>
        </div>
        <div className="modal-body">{props.children}</div>
        {props.footer && <div className="modal-foot">{props.footer}</div>}
      </div>
    </div>
  );
}

export function Confirm(props: {
  title: string;
  text: React.ReactNode;
  confirmLabel?: string;
  danger?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  return (
    <Modal
      title={props.title}
      onClose={props.onCancel}
      size="narrow"
      footer={
        <>
          <button className="btn ghost" onClick={props.onCancel}>{t('ui_cancel')}</button>
          <button className={`btn ${props.danger ? 'danger' : 'primary'}`} onClick={props.onConfirm} autoFocus>
            {props.confirmLabel || t('ui_confirm')}
          </button>
        </>
      }
    >
      <div className="muted">{props.text}</div>
    </Modal>
  );
}

// Inputs --------------------------------------------------------------------------

export function Field(props: { label: React.ReactNode; hint?: React.ReactNode; className?: string; children: React.ReactNode }) {
  return (
    <label className={`field ${props.className || ''}`}>
      <span className="label">{props.label}</span>
      {props.children}
      {props.hint && <span className="hint">{props.hint}</span>}
    </label>
  );
}

/**
 * Number field that keeps the typed text, so "2." or "7,5" can be entered.
 * onChange gets the parsed number (comma or dot), or undefined when empty.
 */
export function NumberInput(props: {
  value: number | null | undefined;
  onChange: (v: number | undefined) => void;
  disabled?: boolean;
  placeholder?: string;
  className?: string;
  style?: React.CSSProperties;
}) {
  const [raw, setRaw] = useState(props.value == null ? '' : String(props.value));
  useEffect(() => {
    const parsed = raw === '' ? undefined : Number(raw.replace(',', '.'));
    if (parsed !== (props.value ?? undefined)) setRaw(props.value == null ? '' : String(props.value));
    // Only react to outside changes of the value.
  }, [props.value]);
  return (
    <input
      className={`input ${props.className || ''}`}
      inputMode="decimal"
      disabled={props.disabled}
      placeholder={props.placeholder}
      style={props.style}
      value={raw}
      onChange={(e) => {
        const next = e.target.value.replace(/[^0-9.,]/g, '');
        setRaw(next);
        const n = Number(next.replace(',', '.'));
        props.onChange(next === '' || Number.isNaN(n) ? undefined : n);
      }}
    />
  );
}

export function Toggle(props: { checked: boolean; onChange: (v: boolean) => void; label?: React.ReactNode; disabled?: boolean }) {
  return (
    <label className="switch">
      <input type="checkbox" checked={props.checked} disabled={props.disabled} onChange={(e) => props.onChange(e.target.checked)} />
      <span className="track" />
      {props.label && <span>{props.label}</span>}
    </label>
  );
}

export function Segmented<T extends string>(props: {
  value: T;
  options: Array<{ value: T; label: React.ReactNode; count?: number }>;
  onChange: (v: T) => void;
}) {
  return (
    <div className="segmented" role="tablist">
      {props.options.map((o) => (
        <button key={o.value} className={o.value === props.value ? 'on' : ''} onClick={() => props.onChange(o.value)} role="tab" aria-selected={o.value === props.value}>
          {o.label}
          {o.count !== undefined && <span className="count">{o.count}</span>}
        </button>
      ))}
    </div>
  );
}

// Feedback ------------------------------------------------------------------------

export function Spinner() {
  return <div className="spinner" aria-label={t('ui_loading')} />;
}

export function Loading() {
  return (
    <div className="loading-center" role="status" aria-live="polite" aria-busy="true">
      <Spinner />
    </div>
  );
}

/** Platzhalter fuer Listen, solange die erste Antwort fehlt (Design aus shared/feedback.css). */
export function ListSkeleton({ rows = 5 }: { rows?: number }) {
  return (
    <div className="list-skeleton">
      <SkeletonList rows={rows} label={t('ui_loading')} />
    </div>
  );
}

/** Fehlerzustand mit verstaendlicher Meldung und "Erneut versuchen". */
export function LoadError({ message, onRetry }: { message?: string; onRetry?: () => void }) {
  return (
    <div className="empty" role="alert">
      <ExclamationCircleIcon style={{ color: 'var(--danger)' }} />
      <b>{hasText('fb_load_failed') ? t('fb_load_failed') : getFeedbackTexts().fbLoadFailed}</b>
      {message && <span>{message}</span>}
      {onRetry && (
        <button type="button" className="btn" onClick={onRetry}>
          <ArrowPathIcon /> {hasText('fb_retry') ? t('fb_retry') : getFeedbackTexts().fbRetry}
        </button>
      )}
    </div>
  );
}

export function Empty(props: { title: string; text?: string; icon?: React.ReactNode; action?: React.ReactNode }) {
  return (
    <div className="empty">
      {props.icon || <InboxIcon />}
      <b>{props.title}</b>
      {props.text && <span>{props.text}</span>}
      {props.action}
    </div>
  );
}

// Status badges -------------------------------------------------------------------

export function Plate({ plate, large }: { plate?: string | null; large?: boolean }) {
  if (!plate) return <span className="faint">-</span>;
  return <span className={`plate ${large ? 'lg' : ''}`}>{plate}</span>;
}

export function initials(name: string) {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  return ((parts[0][0] || '') + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
}

/** Debounced value for search inputs. */
export function useDebounced<T>(value: T, ms = 250): T {
  const [v, setV] = useState(value);
  useEffect(() => {
    const id = window.setTimeout(() => setV(value), ms);
    return () => window.clearTimeout(id);
  }, [value, ms]);
  return v;
}
