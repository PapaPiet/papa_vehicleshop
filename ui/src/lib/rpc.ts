import { hasText, t } from './i18n';
import { RpcCache, type RequestOptions } from '../shared/uiCache';
import { currentActionButton, setFeedbackWriteToasts, trackRequest, withReadTimeout } from '../shared/uiFeedback';
import { LONG_TTL_ACTIONS, NO_CACHE_ACTIONS, READ_ACTIONS } from './cacheActions';

/** Papa OS Web: the NUI shim sets this before the app code runs and routes
 *  `https://<resource>/<callback>` to the web relay (see papa_os_link/docs/ARCHITECTURE.md). */
const papaWeb = (window as unknown as { __PAPA_WEB__?: { resource?: string } }).__PAPA_WEB__;

export const isWebHost = !!papaWeb;

/** NUI calls to this resource. The iframe host is `cfx-nui-<resource>`, which is more
 *  reliable than GetParentResourceName inside an embedded frame. */
const resourceName = (() => {
  if (papaWeb?.resource) return papaWeb.resource;
  const host = window.location.hostname;
  if (host.startsWith('cfx-nui-')) return host.slice('cfx-nui-'.length);
  return 'papa_vehicleshop';
})();

export const isBrowserPreview = !isWebHost && !window.location.hostname.startsWith('cfx-nui-');

export interface RpcResult<T = unknown> {
  ok: boolean;
  data?: T;
  error?: string;
  message?: string;
  [key: string]: unknown;
}

/** Lua cannot tell an empty list from an empty table, so empty lists arrive as {}. Every empty object
 *  becomes [] (harmless for objects that are read by key), so .map/.length always work. */
function emptyToArray(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(emptyToArray);
  if (value && typeof value === 'object') {
    const entries = Object.entries(value as Record<string, unknown>);
    if (entries.length === 0) return [];
    const out: Record<string, unknown> = {};
    for (const [k, v] of entries) out[k] = emptyToArray(v);
    return out;
  }
  return value;
}

export async function fetchNui<T = unknown>(event: string, payload: unknown = {}): Promise<RpcResult<T>> {
  if (isBrowserPreview) {
    return { ok: false, error: 'preview', message: 'Browser preview: no game connection.' };
  }
  const res = await fetch(`https://${resourceName}/${event}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(payload),
  });
  const text = await res.text();
  if (!text) return { ok: false, error: 'empty_response' };
  const out = emptyToArray(JSON.parse(text)) as RpcResult<T>;
  // Errors without a text (e.g. "player_offline" from the Papa OS Web client passthrough)
  // get the matching err_<code> text from the language files, if there is one.
  if (out && out.ok === false && !out.message && typeof out.error === 'string' && hasText(`err_${out.error}`)) {
    out.message = t(`err_${out.error}`);
  }
  return out;
}

const RPC_CALLBACK = 'vehicleshopRpc';

// Erfolgs- und Fehler-Toasts zeigt die App selbst (context.tsx: call mit okText und "Erneut versuchen")
setFeedbackWriteToasts(false);

/** Lokaler Cache der App-Antworten (nur lesende Aktionen, je Figur, Betrieb und Ressourcen-Version). */
export const rpcCache = new RpcCache({
  resource: 'papa_vehicleshop',
  readActions: READ_ACTIONS,
  longTtlActions: LONG_TTL_ACTIONS,
  noCacheActions: NO_CACHE_ACTIONS,
});

/**
 * App-RPC: lesende Aktionen laufen ueber den Cache (stale-while-revalidate, onUpdate meldet frische Daten)
 * und haben ein Zeitlimit; schreibende Aktionen gehen immer an den Server und zeigen am ausloesenden
 * Button den Busy-Zustand (Toasts zeigt die App selbst, siehe context.tsx).
 */
export function rpc<T = unknown>(
  action: string,
  payload: Record<string, unknown> = {},
  opts?: RequestOptions<RpcResult<T>>
): Promise<RpcResult<T>> {
  const body = { action, ...payload };
  const isRead = rpcCache.isReadAction(action);
  const button = isRead ? null : currentActionButton();
  const fetcher = () => {
    const p = fetchNui<T>(RPC_CALLBACK, body);
    if (!isRead) return p;
    return withReadTimeout(p).then((res) => {
      // Zeitlimit: gleicher Text wie die uebrigen Fehler aus den Sprachdateien
      if (res && res.ok === false && res.error === 'timeout' && !res.message && hasText('err_timeout')) {
        return { ...res, message: t('err_timeout') };
      }
      return res;
    });
  };
  return trackRequest(rpcCache.request<RpcResult<T>>(RPC_CALLBACK, body, fetcher, opts), {
    write: !isRead,
    action,
    button,
  });
}

/** Own position in the game world (vehicle position when sitting in one). */
export interface MyPosition { x: number; y: number; z: number; w: number; inVehicle: boolean; street?: string }

export async function myPosition(): Promise<MyPosition | null> {
  const res = await fetchNui<MyPosition>('vehicleshopMyPosition');
  return res.ok && res.data ? res.data : null;
}

/** Sets a GPS waypoint in the game. */
export function waypoint(x: number, y: number) {
  void fetchNui('vehicleshopWaypoint', { x, y });
}
