/**
 * Lokaler Cache fuer lesende RPC-Aktionen (Spezifikation "Ladeanzeigen, Rueckmeldungen, lokaler Cache",
 * Abschnitt B). Gleicher Code in papa_os_police, papa_os_justice und papa_os_mechanic.
 *
 * - Nur Aktionen aus der lesenden Liste der Ressource werden gecacht (unbekannt = nicht cachen).
 * - Schluessel: <resource>@<version>:<identifier der Figur>:<callback>:<action>:<stabiles JSON der Parameter>.
 *   Ohne bekannte Figur gibt es keinen Cache.
 * - Stale-while-revalidate: juenger als TTL -> sofort aus dem Cache, keine Server-Anfrage;
 *   aelter -> sofort aus dem Cache und im Hintergrund neu laden (onUpdate meldet die frische Antwort).
 * - Gleiche gleichzeitige Anfragen werden zusammengefasst.
 * - Jede erfolgreiche schreibende Aktion leert den Cache der Ressource; Figur-, Versions- oder
 *   Schalterwechsel leeren alles.
 * - Antwortet der Server auf eine gecachte Anfrage mit einem Fehler (z. B. not_found nach dem Loeschen durch
 *   andere, no_permission nach Rechteentzug), wird der Eintrag verworfen. Ausnahme: voruebergehende Fehler
 *   (Zeitlimit, Server/Link offline, Rate-Limit), dann bleibt der alte Stand als Rueckfall.
 * - Speicher: IndexedDB, sonst localStorage, sonst nur Arbeitsspeicher. Jeder Zugriff in try/catch,
 *   ohne Speicher laeuft die UI einfach ohne dauerhaften Cache.
 * - Grenzen: max. 5 MB je Ressource (LRU), Eintraege aelter als 24 h werden verworfen.
 * - Antworten, die nach Geheimnissen aussehen (Passwort, PIN, Token, Lizenzschluessel), werden nie gespeichert.
 */

export interface StoredEntry {
  k: string;
  at: number;
  used: number;
  s: string;
}

export interface CacheBackend {
  loadAll(prefix: string): Promise<StoredEntry[]>;
  put(entry: StoredEntry): Promise<void>;
  remove(keys: string[]): Promise<void>;
  removePrefix(prefix: string): Promise<void>;
}

export interface RpcCacheOptions {
  resource: string;
  /** Lesende Aktionen (identisch mit der classify-Liste der Web-RPCs auf dem Server). */
  readActions: Iterable<string>;
  /** Lesende Aktionen mit langer TTL (statische Daten wie Gesetze, Preislisten, Dienstgrade). */
  longTtlActions?: Iterable<string>;
  /** Lesende Aktionen, die nie gecacht werden (Sitzung, Live-Daten wie Online-Spieler). */
  noCacheActions?: Iterable<string>;
  ttlMs?: number;
  longTtlMs?: number;
  maxBytes?: number;
  maxAgeMs?: number;
  /** null = nur Arbeitsspeicher, undefined = automatisch (IndexedDB, sonst localStorage). */
  backend?: CacheBackend | null;
  now?: () => number;
}

export interface CacheIdentity {
  identifier?: string | null;
  version?: string | null;
  enabled?: boolean;
}

export interface RequestOptions<T> {
  /** Wird aufgerufen, wenn eine Hintergrund-Aktualisierung eine geaenderte Antwort liefert. */
  onUpdate?: (value: T) => void;
  /** Cache ueberspringen (Antwort wird trotzdem gespeichert). */
  force?: boolean;
}

export const DEFAULT_TTL_MS = 30_000;
export const LONG_TTL_MS = 10 * 60_000;
export const MAX_BYTES = 5 * 1024 * 1024;
export const MAX_AGE_MS = 24 * 60 * 60_000;

/** Schluesselnamen, deren Antworten nie gespeichert werden. */
const SECRET_KEY_RE = /"(password|passwort|passwd|pin|pincode|pin_code|token|accesstoken|access_token|refreshtoken|secret|licensekey|license_key|apikey|api_key|pairingcode|pairing_code)"\s*:/i;

/** JSON mit sortierten Objektschluesseln, damit gleiche Parameter immer denselben Schluessel ergeben. */
export function stableStringify(value: unknown): string {
  if (value === undefined) return 'null';
  if (value === null || typeof value !== 'object') {
    const out = JSON.stringify(value);
    return out === undefined ? 'null' : out;
  }
  if (Array.isArray(value)) {
    return `[${value.map((v) => stableStringify(v)).join(',')}]`;
  }
  const obj = value as Record<string, unknown>;
  const keys = Object.keys(obj)
    .filter((k) => obj[k] !== undefined && typeof obj[k] !== 'function')
    .sort();
  return `{${keys.map((k) => `${JSON.stringify(k)}:${stableStringify(obj[k])}`).join(',')}}`;
}

/** Fehlercodes, bei denen ein vorhandener Cache-Eintrag bleibt (Server nur gerade nicht erreichbar). */
const TRANSIENT_ERRORS = new Set([
  'timeout',
  'server_offline',
  'link_offline',
  'player_offline',
  'rate_limited',
  'busy',
  'starting',
  'db_not_ready',
  'network',
  'network_error',
  'err_network',
  'internal',
  'no_character',
  'empty_response',
  'empty_nui_response',
  'preview',
]);

/** Voruebergehender Fehler: { error: <Code aus TRANSIENT_ERRORS> }. */
export function isTransientError(res: unknown): boolean {
  if (!res || typeof res !== 'object' || Array.isArray(res)) return false;
  const err = (res as { error?: unknown }).error;
  return typeof err === 'string' && TRANSIENT_ERRORS.has(err);
}

/** Erfolgreiche Antwort: kein { ok:false } und kein Fehlercode. */
export function isSuccessResponse(res: unknown): boolean {
  if (res === null || res === undefined) return false;
  if (typeof res !== 'object') return true;
  if (Array.isArray(res)) return true;
  const r = res as { ok?: unknown; error?: unknown };
  if (r.ok === false) return false;
  if (r.ok !== true && typeof r.error === 'string' && r.error !== '') return false;
  return true;
}

function toSet(list?: Iterable<string>): Set<string> {
  return new Set(list ? Array.from(list) : []);
}

function withTimeout<T>(p: Promise<T>, ms: number, fallback: T): Promise<T> {
  return new Promise<T>((resolve) => {
    const timer = setTimeout(() => resolve(fallback), ms);
    p.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      () => {
        clearTimeout(timer);
        resolve(fallback);
      }
    );
  });
}

// ---------------------------------------------------------------------------------------------
// Speicher-Backends
// ---------------------------------------------------------------------------------------------

const IDB_NAME = 'papa_ui_cache';
const IDB_STORE = 'entries';
const LS_PREFIX = 'papa_ui_cache:';

function idbRequest<T>(req: IDBRequest<T>): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

export function createIndexedDbBackend(): CacheBackend | null {
  let factory: IDBFactory | undefined;
  try {
    factory = typeof indexedDB !== 'undefined' ? indexedDB : undefined;
  } catch {
    factory = undefined;
  }
  if (!factory) return null;
  const idb = factory;
  let dbPromise: Promise<IDBDatabase | null> | null = null;
  const open = (): Promise<IDBDatabase | null> => {
    if (!dbPromise) {
      dbPromise = new Promise<IDBDatabase | null>((resolve) => {
        try {
          const req = idb.open(IDB_NAME, 1);
          req.onupgradeneeded = () => {
            try {
              const db = req.result;
              if (!db.objectStoreNames.contains(IDB_STORE)) db.createObjectStore(IDB_STORE, { keyPath: 'k' });
            } catch {
              /* ohne Store laeuft der Cache nur im Arbeitsspeicher */
            }
          };
          req.onsuccess = () => resolve(req.result);
          req.onerror = () => resolve(null);
          req.onblocked = () => resolve(null);
        } catch {
          resolve(null);
        }
      });
    }
    return dbPromise;
  };
  const withStore = async <T>(mode: IDBTransactionMode, fn: (store: IDBObjectStore) => Promise<T>, fallback: T): Promise<T> => {
    try {
      const db = await open();
      if (!db) return fallback;
      const tx = db.transaction(IDB_STORE, mode);
      return await fn(tx.objectStore(IDB_STORE));
    } catch {
      return fallback;
    }
  };
  const range = (prefix: string) => IDBKeyRange.bound(prefix, `${prefix}￿`);
  return {
    loadAll: (prefix) =>
      withStore('readonly', async (store) => (await idbRequest(store.getAll(range(prefix)))) as StoredEntry[], [] as StoredEntry[]),
    put: (entry) =>
      withStore('readwrite', async (store) => {
        await idbRequest(store.put(entry));
      }, undefined),
    remove: (keys) =>
      withStore('readwrite', async (store) => {
        await Promise.all(keys.map((k) => idbRequest(store.delete(k))));
      }, undefined),
    removePrefix: (prefix) =>
      withStore('readwrite', async (store) => {
        await idbRequest(store.delete(range(prefix)));
      }, undefined),
  };
}

export function createLocalStorageBackend(storage?: Storage): CacheBackend | null {
  let ls: Storage | undefined = storage;
  try {
    if (!ls && typeof localStorage !== 'undefined') ls = localStorage;
    if (!ls) return null;
    const probe = `${LS_PREFIX}probe`;
    ls.setItem(probe, '1');
    ls.removeItem(probe);
  } catch {
    return null;
  }
  const s = ls;
  const keysWith = (prefix: string): string[] => {
    const out: string[] = [];
    try {
      for (let i = 0; i < s.length; i++) {
        const key = s.key(i);
        if (key && key.startsWith(LS_PREFIX + prefix)) out.push(key);
      }
    } catch {
      /* ignorieren */
    }
    return out;
  };
  return {
    loadAll: async (prefix) => {
      const out: StoredEntry[] = [];
      for (const key of keysWith(prefix)) {
        try {
          const raw = s.getItem(key);
          if (!raw) continue;
          const parsed = JSON.parse(raw) as StoredEntry;
          if (parsed && typeof parsed.s === 'string') out.push({ ...parsed, k: key.slice(LS_PREFIX.length) });
        } catch {
          /* defekten Eintrag ueberspringen */
        }
      }
      return out;
    },
    put: async (entry) => {
      try {
        s.setItem(LS_PREFIX + entry.k, JSON.stringify(entry));
      } catch {
        /* Speicher voll oder gesperrt: dann eben nur im Arbeitsspeicher */
      }
    },
    remove: async (keys) => {
      for (const k of keys) {
        try {
          s.removeItem(LS_PREFIX + k);
        } catch {
          /* ignorieren */
        }
      }
    },
    removePrefix: async (prefix) => {
      for (const key of keysWith(prefix)) {
        try {
          s.removeItem(key);
        } catch {
          /* ignorieren */
        }
      }
    },
  };
}

export function createDefaultBackend(): CacheBackend | null {
  return createIndexedDbBackend() ?? createLocalStorageBackend();
}

// ---------------------------------------------------------------------------------------------
// Cache
// ---------------------------------------------------------------------------------------------

interface MemEntry {
  at: number;
  used: number;
  s: string;
}

export class RpcCache {
  private readonly resource: string;
  private readonly readActions: Set<string>;
  private readonly longTtlActions: Set<string>;
  private readonly noCacheActions: Set<string>;
  private readonly ttlMs: number;
  private readonly longTtlMs: number;
  private readonly maxBytes: number;
  private readonly maxAgeMs: number;
  private readonly backend: CacheBackend | null;
  private readonly now: () => number;

  private namespace: string | null = null;
  private enabled = true;
  private mem = new Map<string, MemEntry>();
  private bytes = 0;
  private inflight = new Map<string, Promise<unknown>>();
  private generation = 0;
  private hydration: Promise<void> = Promise.resolve();
  private identityKey = '';

  constructor(opts: RpcCacheOptions) {
    this.resource = opts.resource;
    this.readActions = toSet(opts.readActions);
    this.longTtlActions = toSet(opts.longTtlActions);
    this.noCacheActions = toSet(opts.noCacheActions);
    this.ttlMs = opts.ttlMs ?? DEFAULT_TTL_MS;
    this.longTtlMs = opts.longTtlMs ?? LONG_TTL_MS;
    this.maxBytes = opts.maxBytes ?? MAX_BYTES;
    this.maxAgeMs = opts.maxAgeMs ?? MAX_AGE_MS;
    this.backend = opts.backend === undefined ? createDefaultBackend() : opts.backend;
    this.now = opts.now ?? (() => Date.now());
  }

  /** Alle Schluessel dieser Ressource beginnen damit (jede Version, jede Figur). */
  private get resourcePrefix(): string {
    return `${this.resource}@`;
  }

  isReadAction(action: unknown): boolean {
    return typeof action === 'string' && this.readActions.has(action);
  }

  isCacheable(action: unknown): boolean {
    return this.enabled && this.namespace !== null && this.isReadAction(action) && !this.noCacheActions.has(action as string);
  }

  ttlFor(action: string): number {
    return this.longTtlActions.has(action) ? this.longTtlMs : this.ttlMs;
  }

  get currentNamespace(): string | null {
    return this.namespace;
  }

  get sizeBytes(): number {
    return this.bytes;
  }

  get entryCount(): number {
    return this.mem.size;
  }

  /**
   * Mit jeder Sitzungsantwort aufrufen. Aendert sich Figur, Version oder Schalter, wird alles geleert
   * (auch Eintraege anderer Figuren und Versionen im dauerhaften Speicher).
   */
  setIdentity(identity: CacheIdentity): Promise<void> {
    const identifier = typeof identity.identifier === 'string' ? identity.identifier.trim() : '';
    const version = typeof identity.version === 'string' && identity.version !== '' ? identity.version : '0';
    const enabled = identity.enabled !== false && identifier !== '';
    const key = `${enabled ? 1 : 0}|${version}|${identifier}`;
    if (key === this.identityKey) return this.hydration;
    this.identityKey = key;
    this.dropMemory();
    if (!enabled) {
      this.enabled = identity.enabled !== false;
      this.namespace = null;
      this.hydration = this.backend ? this.backend.removePrefix(this.resourcePrefix).catch(() => undefined) : Promise.resolve();
      return this.hydration;
    }
    this.enabled = true;
    const ns = `${this.resource}@${version}:${identifier}:`;
    this.namespace = ns;
    this.hydration = this.hydrate(ns);
    return this.hydration;
  }

  /** Abmelden / Figur entladen: alles leeren, bis eine neue Sitzung kommt. */
  clearIdentity(): Promise<void> {
    this.identityKey = '';
    this.namespace = null;
    this.dropMemory();
    this.hydration = this.backend ? this.backend.removePrefix(this.resourcePrefix).catch(() => undefined) : Promise.resolve();
    return this.hydration;
  }

  /** Leert den Cache der Ressource (nach jeder erfolgreichen schreibenden Aktion). */
  invalidate(): void {
    this.dropMemory();
    if (this.backend) void this.backend.removePrefix(this.resourcePrefix).catch(() => undefined);
  }

  private dropMemory(): void {
    this.generation += 1;
    this.mem.clear();
    this.inflight.clear();
    this.bytes = 0;
  }

  private async hydrate(ns: string): Promise<void> {
    const backend = this.backend;
    if (!backend) return;
    const gen = this.generation;
    const all = await withTimeout(backend.loadAll(this.resourcePrefix), 1500, [] as StoredEntry[]);
    if (gen !== this.generation || this.namespace !== ns) return;
    const now = this.now();
    const stale: string[] = [];
    for (const e of all) {
      if (!e || typeof e.k !== 'string' || typeof e.s !== 'string') continue;
      if (!e.k.startsWith(ns) || now - e.at > this.maxAgeMs || e.at > now + 60_000) {
        stale.push(e.k);
        continue;
      }
      if (this.mem.has(e.k)) continue;
      this.mem.set(e.k, { at: e.at, used: e.used || e.at, s: e.s });
      this.bytes += e.s.length * 2;
    }
    if (stale.length) void backend.remove(stale).catch(() => undefined);
    this.evict();
  }

  private keyFor(callback: string, payload: unknown): { key: string; action: string } | null {
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return null;
    const { action, ...params } = payload as Record<string, unknown>;
    if (!this.isCacheable(action)) return null;
    return { key: `${this.namespace}${callback}:${action as string}:${stableStringify(params)}`, action: action as string };
  }

  private store(key: string, value: unknown): string | null {
    let s: string;
    try {
      s = JSON.stringify(value);
    } catch {
      return null;
    }
    if (typeof s !== 'string') return null;
    if (SECRET_KEY_RE.test(s)) return null;
    const size = s.length * 2;
    if (size > this.maxBytes / 4) return null;
    const prev = this.mem.get(key);
    if (prev) this.bytes -= prev.s.length * 2;
    const now = this.now();
    this.mem.set(key, { at: now, used: now, s });
    this.bytes += size;
    this.evict();
    if (this.backend && this.mem.has(key)) void this.backend.put({ k: key, at: now, used: now, s }).catch(() => undefined);
    return s;
  }

  /** Einen Eintrag verwerfen (Arbeitsspeicher und dauerhafter Speicher). */
  private drop(key: string): void {
    const prev = this.mem.get(key);
    if (prev) {
      this.mem.delete(key);
      this.bytes -= prev.s.length * 2;
    }
    if (this.backend) void this.backend.remove([key]).catch(() => undefined);
  }

  /** LRU: aelteste Nutzung zuerst raus, bis die Grenze eingehalten ist. */
  private evict(): void {
    if (this.bytes <= this.maxBytes) return;
    const order = Array.from(this.mem.entries()).sort((a, b) => a[1].used - b[1].used);
    const removed: string[] = [];
    for (const [k, e] of order) {
      if (this.bytes <= this.maxBytes) break;
      this.mem.delete(k);
      this.bytes -= e.s.length * 2;
      removed.push(k);
    }
    if (removed.length && this.backend) void this.backend.remove(removed).catch(() => undefined);
  }

  private fetchAndStore<T>(key: string, fetcher: () => Promise<T>): Promise<{ value: T; s: string | null }> {
    const existing = this.inflight.get(key) as Promise<{ value: T; s: string | null }> | undefined;
    if (existing) return existing;
    const gen = this.generation;
    const p = fetcher().then((value) => {
      let s: string | null = null;
      if (gen === this.generation) {
        if (isSuccessResponse(value)) s = this.store(key, value);
        // Fehler (geloescht, keine Rechte mehr ...): alten Stand nicht weiter ausliefern
        else if (!isTransientError(value)) this.drop(key);
      }
      return { value, s };
    });
    this.inflight.set(key, p);
    const done = () => {
      if (this.inflight.get(key) === p) this.inflight.delete(key);
    };
    p.then(done, done);
    return p;
  }

  /**
   * Fuehrt eine RPC-Anfrage ueber den Cache aus. Schreibende Aktionen gehen immer an den Server und
   * leeren nach Erfolg den Cache. Jeder Aufrufer bekommt eine eigene Kopie der Antwort.
   */
  async request<T>(callback: string, payload: unknown, fetcher: () => Promise<T>, opts?: RequestOptions<T>): Promise<T> {
    const action = payload && typeof payload === 'object' ? (payload as { action?: unknown }).action : undefined;
    if (!this.isReadAction(action)) {
      const res = await fetcher();
      if (isSuccessResponse(res)) this.invalidate();
      return res;
    }
    await this.hydration;
    const target = this.keyFor(callback, payload);
    if (!target) return fetcher();
    const { key, action: act } = target;

    const hit = this.mem.get(key);
    const now = this.now();
    if (hit && !opts?.force) {
      if (now - hit.at > this.maxAgeMs) {
        this.mem.delete(key);
        this.bytes -= hit.s.length * 2;
      } else {
        hit.used = now;
        if (now - hit.at >= this.ttlFor(act)) {
          const before = hit.s;
          this.fetchAndStore(key, fetcher).then(
            ({ s }) => {
              if (s !== null && s !== before && opts?.onUpdate) opts.onUpdate(JSON.parse(s) as T);
            },
            () => undefined
          );
        }
        return JSON.parse(hit.s) as T;
      }
    }

    const { value, s } = await this.fetchAndStore(key, fetcher);
    if (s !== null) return JSON.parse(s) as T;
    // Nicht gespeichert (Fehler, Geheimnis, zu gross): Kopie nur bei Objekten, damit zusammengefasste
    // Aufrufer sich nicht gegenseitig die Antwort veraendern.
    if (value && typeof value === 'object') {
      try {
        return JSON.parse(JSON.stringify(value)) as T;
      } catch {
        return value;
      }
    }
    return value;
  }
}
