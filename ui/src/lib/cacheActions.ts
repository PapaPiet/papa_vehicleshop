/**
 * Lesende Aktionen von "vehicleshopRpc" fuer den lokalen Cache.
 * Alles, was hier nicht steht, gilt als schreibend: geht immer an den Server und leert nach Erfolg den Cache.
 */
export const READ_ACTIONS: readonly string[] = [
  'session',
  'dashboard',
  'stock.list',
  'stock.get',
  'displays.list',
  'catalog.list',
  'contracts.list',
  'contracts.suggest',
  'sales.list',
  'sales.stats',
  'players.nearby',
  'finance.preview',
  'tradeins.list',
  'finance.list',
  'account.ledger',
  'policy.get',
  'staff.list',
  'audit.list',
];

/** Statische Daten: lange TTL (10 min). Eigene Aenderungen leeren den Cache trotzdem sofort. */
export const LONG_TTL_ACTIONS: readonly string[] = ['catalog.list', 'policy.get'];

/** Lesend, aber nie gecacht: Sitzung und Live-Daten (Spieler in der Naehe, Lieferstatus). */
export const NO_CACHE_ACTIONS: readonly string[] = [
  'session',
  'players.nearby',
  'dashboard',
  'stock.list',
  'stock.get',
  'tradeins.list',
  'contracts.list',
  'finance.preview',
  'contracts.suggest',
];
