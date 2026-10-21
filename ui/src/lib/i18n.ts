/** Texts come from the resource's language files (locales/translations/*.lua) via the session. */
let strings: Record<string, string> = {};

export function setStrings(next: Record<string, unknown> | undefined) {
  const out: Record<string, string> = {};
  if (next) {
    for (const [k, v] of Object.entries(next)) {
      if (typeof v === 'string') out[k] = v;
    }
  }
  strings = out;
}

export function hasText(key: string) {
  return key in strings;
}

/** Lua-style formatting: %s / %d are replaced in order. Missing keys show the key itself. */
export function t(key: string, ...args: Array<string | number>): string {
  const raw = strings[key];
  if (raw === undefined) return key;
  if (args.length === 0) return raw.replace(/%%/g, '%');
  let i = 0;
  return raw.replace(/%%|%[sd]/g, (m) => {
    if (m === '%%') return '%';
    const v = args[i++];
    return v === undefined ? '' : String(v);
  });
}
