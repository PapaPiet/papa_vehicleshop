import React, { useEffect, useState } from 'react';
import { XMarkIcon } from '@heroicons/react/24/outline';
import { t } from '../lib/i18n';
import { money } from '../lib/format';
import type { Condition, StockStatus, VehicleType } from '../lib/types';

/** Heroicons has no vehicle set, so the types get small outline icons in the same style (24px, stroke 1.5). */
const TYPE_PATHS: Record<VehicleType, string> = {
  car: 'M4.5 14.25 6 9.75A2.25 2.25 0 0 1 8.13 8.25h7.74A2.25 2.25 0 0 1 18 9.75l1.5 4.5m-15 0h15m-15 0v3h2.25v-1.5h10.5v1.5h2.25v-3M7.5 12.75h.008v.008H7.5v-.008Zm9 0h.008v.008H16.5v-.008Z',
  offroad: 'M3.75 13.5 5.25 8.25h9l3 3h2.25v3.75H3.75V13.5Zm3 1.5a1.875 1.875 0 1 0 0 3.75 1.875 1.875 0 0 0 0-3.75Zm10.5 0a1.875 1.875 0 1 0 0 3.75 1.875 1.875 0 0 0 0-3.75Z',
  van: 'M3 15.75V7.5A1.5 1.5 0 0 1 4.5 6h10.19a1.5 1.5 0 0 1 1.06.44l4.06 4.06a1.5 1.5 0 0 1 .44 1.06v4.19H3Zm4.5 0a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3Zm9 0a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3ZM15 6v4.5h5.25',
  truck: 'M8.25 18.75a1.5 1.5 0 0 1-3 0m3 0a1.5 1.5 0 0 0-3 0m3 0h6m-9 0H3.375a1.125 1.125 0 0 1-1.125-1.125V14.25m17.25 4.5a1.5 1.5 0 0 1-3 0m3 0a1.5 1.5 0 0 0-3 0m3 0h1.125c.621 0 1.129-.504 1.09-1.124a17.902 17.902 0 0 0-3.213-9.193 2.056 2.056 0 0 0-1.58-.86H14.25M16.5 18.75h-2.25m0-11.177v-.958c0-.568-.422-1.048-.987-1.106a48.554 48.554 0 0 0-10.026 0 1.106 1.106 0 0 0-.987 1.106v7.635m12-6.677v6.677m0 4.5v-4.5m0 0h-12',
  motorcycle: 'M5.25 17.25a2.25 2.25 0 1 0 0-4.5 2.25 2.25 0 0 0 0 4.5Zm13.5 0a2.25 2.25 0 1 0 0-4.5 2.25 2.25 0 0 0 0 4.5ZM5.25 15l4.5-4.5h4.5l2.25 2.25M13.5 7.5h2.25l3 7.5M9 10.5 7.5 7.5H6',
  bicycle: 'M5.25 17.25a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm13.5 0a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM5.25 14.25 9 8.25h6l3.75 6M9 8.25 12 14.25h-6.75M14.25 6h2.25',
  boat: 'M3 15.75 4.5 19.5h15l1.5-3.75H3Zm1.5 0V12h15v3.75M12 12V4.5l5.25 5.25H12',
  heli: 'M3 6h18M12 6v3m-6 3.75A3.75 3.75 0 0 1 9.75 9h4.5a3.75 3.75 0 0 1 3.75 3.75v.75a2.25 2.25 0 0 1-2.25 2.25H8.25A2.25 2.25 0 0 1 6 13.5v-.75Zm0 0H3m4.5 6h9M9 15.75v2.25m6-2.25v2.25',
  plane: 'M12 3v6.75L21 14.25v1.5l-9-2.25v4.5l2.25 1.5v1.5L12 20.25 9.75 21v-1.5L12 18V13.5L3 15.75v-1.5L12 9.75',
};

export function VehicleTypeIcon({ type, size = 18 }: { type: VehicleType; size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={TYPE_PATHS[type] || TYPE_PATHS.car} />
    </svg>
  );
}

export function TypeBadge({ type }: { type: VehicleType }) {
  return (
    <span className="vtype" title={t(`vtype_${type}`)}>
      <VehicleTypeIcon type={type} />
    </span>
  );
}

const STATUS_TONE: Record<StockStatus, string> = {
  transit: '',
  waiting: 'warn',
  pickup: 'accent',
  storage: '',
  display: 'ok',
  testdrive: 'accent',
  out: 'warn',
  sold: 'ok',
  removed: 'danger',
};

export function StatusBadge({ status }: { status: StockStatus }) {
  return <span className={`badge ${STATUS_TONE[status] || ''}`}>{t(`status_${status}`)}</span>;
}

export function damageOf(c?: Condition | null): number {
  if (!c) return 0;
  const engine = 1 - (Number(c.engine ?? 1000) / 1000);
  const body = 1 - (Number(c.body ?? 1000) / 1000);
  return Math.max(0, Math.min(100, Math.round(Math.max(engine, body) * 100)));
}

/** Condition as a bar: 100 % = like new. */
export function ConditionMeter({ condition, compact }: { condition?: Condition | null; compact?: boolean }) {
  const health = 100 - damageOf(condition);
  const tone = health >= 80 ? '' : health >= 50 ? 'warn' : 'danger';
  return (
    <div className="stack s8" style={{ gap: 4 }}>
      {!compact && (
        <div className="row between">
          <span className="faint" style={{ fontSize: 12 }}>{t('ui_condition')}</span>
          <span style={{ fontSize: 12, fontWeight: 600 }}>{health} %</span>
        </div>
      )}
      <div className={`meter ${tone}`} title={`${health} %`}>
        <span style={{ width: `${health}%` }} />
      </div>
    </div>
  );
}

/** Live countdown to a timestamp in ms. */
export function Countdown({ to }: { to: number }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, []);
  const left = Math.max(0, Math.floor((to - now) / 1000));
  if (left <= 0) return <span className="countdown">{t('ui_arriving')}</span>;
  const h = Math.floor(left / 3600);
  const m = Math.floor((left % 3600) / 60);
  const s = left % 60;
  const text = h > 0 ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}` : `${m}:${String(s).padStart(2, '0')}`;
  return <span className="countdown">{text}</span>;
}

export function minutesText(minutes?: number | null) {
  const m = Math.round(Number(minutes) || 0);
  if (m >= 60) {
    const h = Math.floor(m / 60);
    const r = m % 60;
    return r ? t('time_hours_minutes', h, r) : t('time_hours', h);
  }
  return t('time_minutes', m);
}

export function Drawer(props: { title: React.ReactNode; onClose: () => void; children: React.ReactNode; footer?: React.ReactNode; icon?: React.ReactNode }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') props.onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [props]);
  return (
    <>
      <div className="drawer-backdrop" onClick={props.onClose} />
      <aside className="drawer" role="dialog">
        <div className="drawer-head">
          {props.icon}
          <div className="h2 flex1">{props.title}</div>
          <button className="icon-btn" onClick={props.onClose} aria-label={t('ui_close')}>
            <XMarkIcon />
          </button>
        </div>
        <div className="drawer-body">{props.children}</div>
        {props.footer && <div className="drawer-foot">{props.footer}</div>}
      </aside>
    </>
  );
}

export function Kpi(props: { label: string; value: React.ReactNode; sub?: React.ReactNode; icon: React.ComponentType<React.SVGProps<SVGSVGElement>>; onClick?: () => void }) {
  return (
    <div className={`card kpi ${props.onClick ? 'clickable' : ''}`} onClick={props.onClick}>
      <div className="ico"><props.icon /></div>
      <span className="label">{props.label}</span>
      <span className="value">{props.value}</span>
      {props.sub && <span className="sub">{props.sub}</span>}
    </div>
  );
}

/** Simple bar chart (revenue per day). */
export function Bars({ data }: { data: Array<{ label: string; value: number; tip: string }> }) {
  const max = Math.max(1, ...data.map((d) => d.value));
  return (
    <div className="bars">
      {data.map((d) => (
        <div key={d.label} className="bar" style={{ height: `${Math.max(3, (d.value / max) * 100)}%` }}>
          <span className="tip">{d.tip}</span>
        </div>
      ))}
    </div>
  );
}

export function Money({ value }: { value?: number | null }) {
  return <span style={{ fontVariantNumeric: 'tabular-nums' }}>{money(value)}</span>;
}
