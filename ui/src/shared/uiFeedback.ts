/**
 * Rueckmeldungen fuer RPC-Anfragen (Spezifikation "Ladeanzeigen, Rueckmeldungen, lokaler Cache", Abschnitt A).
 * Gleicher Code in papa_os_police, papa_os_justice und papa_os_mechanic.
 *
 * - Zaehlt laufende Anfragen: nach 400 ms dezente Fortschrittsanzeige, nach 8 s Hinweis "Dauert laenger...".
 * - Lesende Anfragen bekommen ein Zeitlimit (Fehler "timeout"), schreibende nie (sonst koennte ein
 *   "Erneut versuchen" doppelt speichern).
 * - Schreibende Anfragen aus einem Klick: der ausloesende Button zeigt den Busy-Zustand und nimmt bis zur
 *   Antwort keine Klicks an; danach Toast (Gespeichert / Fehler mit "Erneut versuchen").
 * - Fehlercodes werden auf verstaendliche Texte abgebildet (Texte kommen aus den Locales der Ressource).
 */

export type ToastKind = 'ok' | 'error' | 'info';

export interface FeedbackToast {
  id: number;
  kind: ToastKind;
  text: string;
  retry?: () => void;
}

export interface FeedbackState {
  /** Laufende Anfragen. */
  pending: number;
  /** Mindestens eine Anfrage laeuft laenger als 400 ms. */
  busy: boolean;
  /** Mindestens eine Anfrage laeuft laenger als 8 s. */
  slow: boolean;
  toasts: FeedbackToast[];
}

/** Texte fuer Rueckmeldungen, Schluessel wie in den Locales (ui-Tabelle). */
export interface FeedbackTexts {
  fbLoading: string;
  fbSlow: string;
  fbRetry: string;
  fbReload: string;
  fbSaved: string;
  fbDeleted: string;
  fbSent: string;
  fbEmpty: string;
  fbLoadFailed: string;
  fbDismiss: string;
  errForbidden: string;
  errServerOffline: string;
  errTimeout: string;
  errPlayerOffline: string;
  errWebUnsupported: string;
  errUnverifiedResource: string;
  errRateLimited: string;
  errUnknownCallback: string;
  errGeneric: string;
}

export const FEEDBACK_TEXT_DEFAULTS: FeedbackTexts = {
  fbLoading: 'Wird geladen...',
  fbSlow: 'Dauert länger als üblich...',
  fbRetry: 'Erneut versuchen',
  fbReload: 'Neu laden',
  fbSaved: 'Gespeichert',
  fbDeleted: 'Gelöscht',
  fbSent: 'Gesendet',
  fbEmpty: 'Noch keine Einträge',
  fbLoadFailed: 'Laden fehlgeschlagen',
  fbDismiss: 'Schließen',
  errForbidden: 'Dafür fehlen dir die Rechte.',
  errServerOffline: 'Keine Verbindung zum Server.',
  errTimeout: 'Der Server antwortet nicht (Zeitüberschreitung).',
  errPlayerOffline: 'Deine Figur ist gerade nicht im Spiel online.',
  errWebUnsupported: 'Diese Funktion ist im Web nicht verfügbar.',
  errUnverifiedResource: 'Diese Ressource ist nicht verifiziert.',
  errRateLimited: 'Zu viele Anfragen, bitte kurz warten.',
  errUnknownCallback: 'Diese Funktion ist auf dem Server nicht verfügbar.',
  errGeneric: 'Es ist ein Fehler aufgetreten.',
};

export const PROGRESS_DELAY_MS = 400;
export const SLOW_DELAY_MS = 8000;
export const READ_TIMEOUT_MS = 30000;
const TOAST_MS = 3500;
const TOAST_ERROR_MS = 7000;

/** Bekannte Fehlercodes (Kern, Link, Webapp und Ressourcen) -> Textschluessel. */
const ERROR_KEYS: Record<string, keyof FeedbackTexts> = {
  forbidden: 'errForbidden',
  no_permission: 'errForbidden',
  no_access: 'errForbidden',
  not_allowed: 'errForbidden',
  missing_permission: 'errForbidden',
  server_offline: 'errServerOffline',
  offline: 'errServerOffline',
  network: 'errServerOffline',
  network_error: 'errServerOffline',
  empty_nui_response: 'errServerOffline',
  empty_response: 'errServerOffline',
  link_offline: 'errServerOffline',
  timeout: 'errTimeout',
  rpc_timeout: 'errTimeout',
  player_offline: 'errPlayerOffline',
  web_unsupported: 'errWebUnsupported',
  unverified_resource: 'errUnverifiedResource',
  rate_limited: 'errRateLimited',
  unknown_callback: 'errUnknownCallback',
};

export function feedbackErrorKey(code: unknown): keyof FeedbackTexts | null {
  if (typeof code !== 'string') return null;
  return ERROR_KEYS[code] ?? null;
}

/** Text fuer einen Fehlercode: bekannter Code -> Locale-Text, sonst Servertext, sonst allgemeiner Fehler. */
export function feedbackErrorText(code: unknown, texts: Partial<FeedbackTexts>, serverMessage?: unknown): string {
  const key = feedbackErrorKey(code);
  if (key) return texts[key] || FEEDBACK_TEXT_DEFAULTS[key];
  if (typeof serverMessage === 'string' && serverMessage.trim() !== '') return serverMessage;
  return texts.errGeneric || FEEDBACK_TEXT_DEFAULTS.errGeneric;
}

// ---------------------------------------------------------------------------------------------
// Zustand
// ---------------------------------------------------------------------------------------------

let state: FeedbackState = { pending: 0, busy: false, slow: false, toasts: [] };
const listeners = new Set<(s: FeedbackState) => void>();
let texts: Partial<FeedbackTexts> = {};
let toastWrites = true;
let nextToastId = 1;
const startedAt = new Map<number, number>();
let nextRequestId = 1;
let tickTimer: ReturnType<typeof setTimeout> | null = null;

function emit(next: Partial<FeedbackState>) {
  state = { ...state, ...next };
  for (const l of Array.from(listeners)) l(state);
}

export function subscribeFeedback(listener: (s: FeedbackState) => void): () => void {
  listeners.add(listener);
  listener(state);
  return () => {
    listeners.delete(listener);
  };
}

export function getFeedbackState(): FeedbackState {
  return state;
}

export function setFeedbackTexts(next: Partial<FeedbackTexts> | null | undefined) {
  texts = { ...(next ?? {}) };
}

export function getFeedbackTexts(): FeedbackTexts {
  const out = { ...FEEDBACK_TEXT_DEFAULTS };
  for (const k of Object.keys(out) as (keyof FeedbackTexts)[]) {
    const v = texts[k];
    if (typeof v === 'string' && v !== '') out[k] = v;
  }
  return out;
}

/** false = Erfolgs-/Fehler-Toasts zeigt die App selbst (z. B. Werkstatt-App), hier nur Busy und Fortschritt. */
export function setFeedbackWriteToasts(enabled: boolean) {
  toastWrites = enabled;
}

function recompute() {
  const now = Date.now();
  let busy = false;
  let slow = false;
  let nextCheck = Infinity;
  for (const at of startedAt.values()) {
    const age = now - at;
    if (age >= PROGRESS_DELAY_MS) busy = true;
    else nextCheck = Math.min(nextCheck, PROGRESS_DELAY_MS - age);
    if (age >= SLOW_DELAY_MS) slow = true;
    else nextCheck = Math.min(nextCheck, SLOW_DELAY_MS - age);
  }
  if (tickTimer) {
    clearTimeout(tickTimer);
    tickTimer = null;
  }
  if (nextCheck !== Infinity) tickTimer = setTimeout(recompute, nextCheck + 5);
  if (busy !== state.busy || slow !== state.slow || startedAt.size !== state.pending) {
    emit({ pending: startedAt.size, busy, slow });
  }
}

export function showToast(kind: ToastKind, text: string, retry?: () => void): number {
  const id = nextToastId++;
  const toast: FeedbackToast = { id, kind, text, retry };
  emit({ toasts: [...state.toasts.slice(-3), toast] });
  setTimeout(() => dismissToast(id), kind === 'error' ? TOAST_ERROR_MS : TOAST_MS);
  return id;
}

export function dismissToast(id: number) {
  if (!state.toasts.some((t) => t.id === id)) return;
  emit({ toasts: state.toasts.filter((t) => t.id !== id) });
}

// ---------------------------------------------------------------------------------------------
// Busy-Buttons
// ---------------------------------------------------------------------------------------------

const BUSY_ATTR = 'data-papa-busy';
let guardInstalled = false;

/** Klicks auf Buttons im Busy-Zustand abfangen (kein Doppelklick, keine doppelte Anfrage). */
function installClickGuard() {
  if (guardInstalled || typeof document === 'undefined') return;
  guardInstalled = true;
  const block = (ev: Event) => {
    const target = ev.target as Element | null;
    if (target && typeof target.closest === 'function' && target.closest(`[${BUSY_ATTR}]`)) {
      ev.preventDefault();
      ev.stopPropagation();
    }
  };
  document.addEventListener('click', block, true);
  document.addEventListener('submit', block, true);
}

/**
 * Button der gerade laufenden Benutzeraktion (Klick, Enter, Absenden). Nur waehrend des Ereignisses selbst
 * gesetzt: Anfragen aus Effekten (Laden beim Oeffnen einer Ansicht) bekommen keinen Busy-Zustand und keinen Toast.
 */
export function currentActionButton(): HTMLElement | null {
  if (typeof window === 'undefined') return null;
  const ev = (window as unknown as { event?: Event }).event;
  if (!ev) return null;
  if (ev.type !== 'click' && ev.type !== 'submit' && ev.type !== 'keydown') return null;
  if (ev.type === 'keydown' && (ev as KeyboardEvent).key !== 'Enter') return null;
  const target = ev.target as Element | null;
  if (!target || typeof target.closest !== 'function') return null;
  const btn = target.closest('button, [role="button"], input[type="submit"]') as HTMLElement | null;
  if (btn) return btn;
  const form = target.closest('form');
  if (form) return form.querySelector('button[type="submit"], input[type="submit"]') as HTMLElement | null;
  return null;
}

function markBusy(el: HTMLElement): () => void {
  installClickGuard();
  const count = Number(el.getAttribute(BUSY_ATTR) || '0') + 1;
  el.setAttribute(BUSY_ATTR, String(count));
  el.setAttribute('aria-busy', 'true');
  el.setAttribute('aria-disabled', 'true');
  el.classList.add('pf-busy');
  return () => {
    const left = Number(el.getAttribute(BUSY_ATTR) || '1') - 1;
    if (left > 0) {
      el.setAttribute(BUSY_ATTR, String(left));
      return;
    }
    el.removeAttribute(BUSY_ATTR);
    el.removeAttribute('aria-busy');
    el.removeAttribute('aria-disabled');
    el.classList.remove('pf-busy');
  };
}

function successTextFor(action: string): string {
  const t = getFeedbackTexts();
  const a = action.toLowerCase();
  if (/^(delete|remove|archive|revoke|unlink|clear)/.test(a) || a.includes('.delete') || a.includes('.remove')) return t.fbDeleted;
  if (/^(send|submit|release|notify|forward|return|transfer|request)/.test(a) || a.includes('.send') || a.includes('.submit')) return t.fbSent;
  return t.fbSaved;
}

// ---------------------------------------------------------------------------------------------
// Anfragen begleiten
// ---------------------------------------------------------------------------------------------

export interface TrackOptions {
  /** Schreibende Aktion (Busy-Button + Toast). */
  write: boolean;
  /** Aktionsname fuer den Erfolgstext. */
  action?: string;
  /** Button der Benutzeraktion (aus currentActionButton()). */
  button?: HTMLElement | null;
  /** Kein Erfolgs-Toast (Aktionen ohne gespeicherte Aenderung, z. B. Vorschau); Fehler werden trotzdem gemeldet. */
  quiet?: boolean;
}

function responseError(res: unknown): { code: unknown; message: unknown } | null {
  if (!res || typeof res !== 'object' || Array.isArray(res)) return null;
  const r = res as { ok?: unknown; error?: unknown; message?: unknown };
  if (r.ok === false) return { code: r.error, message: r.message };
  if (r.ok !== true && typeof r.error === 'string' && r.error !== '') return { code: r.error, message: r.message };
  return null;
}

/** Begleitet eine Anfrage: Fortschritt, Busy-Button, Toast. Das Ergebnis bleibt unveraendert. */
export function trackRequest<T>(promise: Promise<T>, opts: TrackOptions): Promise<T> {
  const id = nextRequestId++;
  startedAt.set(id, Date.now());
  recompute();
  const button = opts.write ? opts.button ?? null : null;
  const release = button ? markBusy(button) : null;
  const finish = () => {
    startedAt.delete(id);
    recompute();
    if (release) release();
  };
  // Retry klickt denselben Button noch einmal, damit die Ansicht ihre eigene Logik erneut ausfuehrt.
  const retry =
    button && typeof button.click === 'function'
      ? () => {
          if (button.isConnected) button.click();
        }
      : undefined;
  return promise.then(
    (res) => {
      finish();
      if (button && toastWrites) {
        const err = responseError(res);
        if (err) showToast('error', feedbackErrorText(err.code, getFeedbackTexts(), err.message), retry);
        else if (!opts.quiet) showToast('ok', successTextFor(opts.action ?? ''));
      }
      return res;
    },
    (e: unknown) => {
      finish();
      if (button && toastWrites) showToast('error', getFeedbackTexts().errServerOffline, retry);
      throw e;
    }
  );
}

/** Zeitlimit fuer lesende Anfragen: liefert danach { ok:false, error:"timeout" }. */
export function withReadTimeout<T>(promise: Promise<T>, ms: number = READ_TIMEOUT_MS): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => resolve({ ok: false, error: 'timeout' } as unknown as T), ms);
    promise.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (e) => {
        clearTimeout(timer);
        reject(e);
      }
    );
  });
}

// ---------------------------------------------------------------------------------------------
// Bereit-Meldung an Papa OS
// ---------------------------------------------------------------------------------------------

let readySent = false;
let loadingSent = false;

/**
 * Meldet dem Papa-OS-Fenster frueh "laedt" (papa:app:loading): der Rahmen wartet dann sicher auf
 * notifyAppReady(), statt die App nach dem load-Ereignis halb fertig anzuzeigen. Nur einmal, nur im iframe.
 * Wer das aufruft, muss spaeter auch notifyAppReady() aufrufen (sonst erst nach dem Zeitlimit des Rahmens sichtbar).
 */
export function notifyAppLoading() {
  if (loadingSent || readySent) return;
  loadingSent = true;
  try {
    if (typeof window !== 'undefined' && window.parent && window.parent !== window) {
      window.parent.postMessage({ type: 'papa:app:loading' }, '*');
    }
  } catch {
    /* ohne Parent nichts zu melden */
  }
}

/** Meldet dem Papa-OS-Fenster (ingame NUI oder Web-Rahmen), dass die App bereit ist. Nur einmal. */
export function notifyAppReady() {
  if (readySent) return;
  readySent = true;
  try {
    if (typeof window !== 'undefined' && window.parent && window.parent !== window) {
      window.parent.postMessage({ type: 'papa:app:ready' }, '*');
    }
  } catch {
    /* ohne Parent nichts zu melden */
  }
}
