import React, { useCallback, useEffect, useState } from 'react';
import {
  BuildingLibraryIcon,
  ArchiveBoxIcon,
  RectangleGroupIcon,
  TruckIcon,
  ArrowsRightLeftIcon,
  ExclamationTriangleIcon,
  UserGroupIcon,
  ClipboardDocumentListIcon,
} from '@heroicons/react/24/outline';
import { useApp } from '../context';
import { t } from '../../lib/i18n';
import { money, dateTime } from '../../lib/format';
import type { Dashboard } from '../../lib/types';
import { Empty, ListSkeleton, Plate } from '../../components/ui';
import { Bars, Countdown, Kpi, StatusBadge, TypeBadge } from '../../components/vs';

export function DashboardView() {
  const { call, go, session } = useApp();
  const [data, setData] = useState<Dashboard | null>(null);

  const load = useCallback(async () => {
    const d = await call<Dashboard>('dashboard');
    if (d) setData(d);
  }, [call]);

  useEffect(() => {
    void load();
    const id = window.setInterval(() => void load(), 30000);
    return () => window.clearInterval(id);
  }, [load]);

  if (!data) return <ListSkeleton rows={6} />;
  const c = data.counts || {};
  const week = data.daily.slice(-7);
  const revenue7 = week.reduce((s, d) => s + d.revenue, 0);
  const sales7 = week.reduce((s, d) => s + d.count, 0);

  return (
    <div className="stack s20">
      {!session.shop.ownerId && session.shop.type !== 'npc' && (
        <div className="notice danger"><ExclamationTriangleIcon /><span>{t('ui_no_owner_hint')}</span></div>
      )}
      <div className="kpis">
        {data.balance !== undefined && data.balance !== null ? (
          <Kpi label={t('ui_balance')} value={money(data.balance)} icon={BuildingLibraryIcon} onClick={() => go({ name: 'account' })} />
        ) : (
          <Kpi label={t('ui_staff_on_duty')} value={data.staffOnDuty} icon={UserGroupIcon} />
        )}
        <Kpi label={t('ui_in_stock')} value={(c.storage || 0) + (c.display || 0) + (c.out || 0) + (c.testdrive || 0)} sub={t('ui_in_stock_sub', c.storage || 0, c.display || 0)} icon={ArchiveBoxIcon} onClick={() => go({ name: 'stock' })} />
        <Kpi label={t('ui_displays_used')} value={`${data.displaysUsed}/${data.displays}`} icon={RectangleGroupIcon} onClick={() => go({ name: 'displays' })} />
        <Kpi label={t('ui_incoming')} value={(c.transit || 0) + (c.waiting || 0) + (c.pickup || 0)} sub={t('ui_incoming_sub', c.transit || 0, c.waiting || 0)} icon={TruckIcon} onClick={() => go({ name: 'deliveries' })} />
      </div>

      <div className="grid c3">
        <div className="card span2">
          <div className="card-head">
            <div className="h2">{t('ui_revenue_14')}</div>
            <span className="muted">{t('ui_last_7', money(revenue7), sales7)}</span>
          </div>
          <div className="card-body">
            <Bars data={data.daily.map((d) => ({ label: d.day, value: d.revenue, tip: `${d.day.slice(5)} · ${money(d.revenue)} · ${d.count}` }))} />
          </div>
        </div>
        <div className="card">
          <div className="card-head"><div className="h2">{t('ui_attention')}</div></div>
          <div className="card-body stack s8">
            <div className="row between"><span className="row"><ArrowsRightLeftIcon style={{ width: 16 }} />{t('nav_tradeins')}</span><b>{data.tradeinsOpen}</b></div>
            <div className="row between"><span className="row"><ClipboardDocumentListIcon style={{ width: 16 }} />{t('ui_contracts_open')}</span><b>{data.contractsOpen}</b></div>
            <div className="row between"><span className="row"><ExclamationTriangleIcon style={{ width: 16 }} />{t('ui_finance_defaulted')}</span><b className={data.financeDefaulted > 0 ? 'accent' : ''}>{data.financeDefaulted}</b></div>
            <div className="row between"><span className="row"><UserGroupIcon style={{ width: 16 }} />{t('ui_staff_on_duty')}</span><b>{data.staffOnDuty}</b></div>
          </div>
        </div>
      </div>

      <div className="grid c2">
        <div className="card">
          <div className="card-head"><div className="h2">{t('ui_arrivals')}</div></div>
          {data.arrivals.length === 0 && data.waiting.length === 0 ? (
            <Empty title={t('ui_no_arrivals')} />
          ) : (
            <div>
              {data.waiting.map((v) => (
                <div key={v.id} className="list-item" onClick={() => go({ name: 'deliveries' })}>
                  <TypeBadge type={v.vtype} />
                  <div className="flex1">
                    <div className="h3 ellipsis">{v.label}</div>
                    <div className="faint" style={{ fontSize: 12 }}>{v.deliveryLabel}</div>
                  </div>
                  <StatusBadge status={v.status} />
                </div>
              ))}
              {data.arrivals.map((v) => (
                <div key={v.id} className="list-item" onClick={() => go({ name: 'deliveries' })}>
                  <TypeBadge type={v.vtype} />
                  <div className="flex1">
                    <div className="h3 ellipsis">{v.label}</div>
                    <div className="faint" style={{ fontSize: 12 }}>{v.deliveryLabel}</div>
                  </div>
                  <Countdown to={v.eta} />
                </div>
              ))}
            </div>
          )}
        </div>
        <div className="card">
          <div className="card-head"><div className="h2">{t('ui_recent_sales')}</div></div>
          {data.recentSales.length === 0 ? (
            <Empty title={t('ui_no_sales')} />
          ) : (
            <div>
              {data.recentSales.map((s) => (
                <div key={s.id} className="list-item" onClick={() => go({ name: 'sales' })}>
                  <div className="flex1">
                    <div className="h3 ellipsis">{s.label}</div>
                    <div className="faint" style={{ fontSize: 12 }}>{s.buyerName} · {dateTime(s.createdAt)}</div>
                  </div>
                  <Plate plate={s.plate} />
                  <b>{money(s.price)}</b>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
