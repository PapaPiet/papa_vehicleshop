export interface DateTimeFormat {
  locale?: string;
  dateFormat?: string;
  timeFormat?: string;
}

let fmt: DateTimeFormat = { locale: 'de-DE', dateFormat: 'dmy', timeFormat: '24h' };
let currency = '$';

export function setDateTimeFormat(next?: DateTimeFormat | null) {
  if (next) fmt = { ...fmt, ...next };
}

export function setCurrency(next?: string) {
  if (next) currency = next;
}

export function getCurrency() {
  return currency;
}

export function money(value: number | undefined | null, withSymbol = true): string {
  const n = Math.round(Number(value) || 0);
  const s = new Intl.NumberFormat(fmt.locale || 'de-DE', { maximumFractionDigits: 0 }).format(n);
  return withSymbol ? `${s} ${currency}` : s;
}

export function num(value: number | undefined | null, digits = 2): string {
  const n = Number(value) || 0;
  return new Intl.NumberFormat(fmt.locale || 'de-DE', { maximumFractionDigits: digits }).format(n);
}

function dateOptions(): Intl.DateTimeFormatOptions {
  switch (fmt.dateFormat) {
    case 'long':
      return { day: 'numeric', month: 'long', year: 'numeric' };
    case 'medium':
      return { day: 'numeric', month: 'short', year: 'numeric' };
    case 'dmy_short':
    case 'short':
      return { day: '2-digit', month: '2-digit', year: '2-digit' };
    default:
      return { day: '2-digit', month: '2-digit', year: 'numeric' };
  }
}

export function date(ms?: number | null): string {
  if (!ms) return '-';
  return new Intl.DateTimeFormat(fmt.locale || 'de-DE', dateOptions()).format(new Date(ms));
}

export function time(ms?: number | null): string {
  if (!ms) return '-';
  return new Intl.DateTimeFormat(fmt.locale || 'de-DE', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: fmt.timeFormat === '12h',
  }).format(new Date(ms));
}

export function dateTime(ms?: number | null): string {
  if (!ms) return '-';
  return `${date(ms)} ${time(ms)}`;
}

export function relative(ms?: number | null): string {
  if (!ms) return '-';
  const diff = ms - Date.now();
  const rtf = new Intl.RelativeTimeFormat(fmt.locale || 'de-DE', { numeric: 'auto' });
  const abs = Math.abs(diff);
  const min = 60 * 1000;
  const hour = 60 * min;
  const day = 24 * hour;
  if (abs < hour) return rtf.format(Math.round(diff / min), 'minute');
  if (abs < day) return rtf.format(Math.round(diff / hour), 'hour');
  if (abs < 30 * day) return rtf.format(Math.round(diff / day), 'day');
  return date(ms);
}
