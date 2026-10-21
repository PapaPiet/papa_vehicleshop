import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { HandRaisedIcon } from '@heroicons/react/24/outline';
import { useApp } from '../context';
import { t } from '../../lib/i18n';
import { money, dateTime } from '../../lib/format';
import type { DayStat, Sale, StockItem } from '../../lib/types';
import { Empty, ListSkeleton, Modal, Plate, Segmented } from '../../components/ui';
import { Bars, Kpi, TypeBadge } from '../../components/vs';
import { SellModal } from './Stock';
import { BanknotesIcon, ChartBarIcon, ScaleIcon } from '@heroicons/react/24/outline';

function PickVehicle(props: { onPick: (v: StockItem) => void; onClose: () => void }) {
  const { call } = useApp();
  const [list, setList] = useState<StockItem[] | null>(null);
  useEffect(() => {
    void call<StockItem[]>('stock.list', { statuses: ['storage', 'display'] }).then((d) => setList(d || []));
  }, [call]);
  return (
    <Modal title={t('ui_pick_vehicle')} onClose={props.onClose}>
      {!list ? <ListSkeleton rows={3} /> : list.length === 0 ? <Empty title={t('ui_stock_empty')} /> : (
        <div className="card">
          {list.map((v) => (
            <div key={v.id} className="list-item" onClick={() => props.onPick(v)}>
              <TypeBadge type={v.vtype} />
              <div className="flex1"><div className="h3">{v.label}</div><div className="faint" style={{ fontSize: 12 }}>{t(`status_${v.status}`)}</div></div>
              <Plate plate={v.plate} />
              <b>{money(v.price)}</b>
            </div>
          ))}
        </div>
      )}
    </Modal>
  );
}

export function SalesView() {
  const { call, session } = useApp();
  const [sales, setSales] = useState<Sale[] | null>(null);
  const [stats, setStats] = useState<DayStat[] | null>(null);
  const [range, setRange] = useState<'14' | '30' | '90'>('30');
  const [pick, setPick] = useState(false);
  const [sellVehicle, setSellVehicle] = useState<StockItem | null>(null);

  const load = useCallback(async () => {
    const [s, st] = await Promise.all([call<Sale[]>('sales.list', { limit: 100 }), call<DayStat[]>('sales.stats', { days: Number(range) })]);
    setSales(s || []);
    setStats(st || []);
  }, [call, range]);

  useEffect(() => {
    void load();
  }, [load]);

  const sum = useMemo(() => {
    const s = stats || [];
    return {
      revenue: s.reduce((a, d) => a + d.revenue, 0),
      profit: s.reduce((a, d) => a + d.profit, 0),
      count: s.reduce((a, d) => a + d.count, 0),
    };
  }, [stats]);

  return (
    <div className="stack s20">
      <div className="toolbar">
        <Segmented value={range} onChange={setRange} options={[
          { value: '14', label: t('ui_days', 14) },
          { value: '30', label: t('ui_days', 30) },
          { value: '90', label: t('ui_days', 90) },
        ]} />
        <div className="flex1" />
        {session.flags.sell && <button className="btn primary" onClick={() => setPick(true)}><HandRaisedIcon />{t('ui_new_sale')}</button>}
      </div>
      <div className="kpis">
        <Kpi label={t('ui_revenue')} value={money(sum.revenue)} icon={BanknotesIcon} />
        <Kpi label={t('ui_profit')} value={money(sum.profit)} sub={t('ui_profit_sub')} icon={ScaleIcon} />
        <Kpi label={t('ui_sales_count')} value={sum.count} icon={ChartBarIcon} />
        <Kpi label={t('ui_avg_price')} value={money(sum.count ? sum.revenue / sum.count : 0)} icon={BanknotesIcon} />
      </div>
      {stats && (
        <div className="card card-body">
          <Bars data={stats.map((d) => ({ label: d.day, value: d.revenue, tip: `${d.day.slice(5)} · ${money(d.revenue)} · ${d.count}` }))} />
        </div>
      )}
      <div className="card">
        {!sales ? <ListSkeleton rows={6} /> : sales.length === 0 ? <Empty title={t('ui_no_sales')} /> : (
          <table className="table">
            <thead><tr><th>{t('ui_date')}</th><th>{t('ui_vehicle')}</th><th className="hide-mobile">{t('ui_buyer')}</th><th className="hide-mobile">{t('ui_seller')}</th><th>{t('ui_channel')}</th><th className="num">{t('ui_price')}</th></tr></thead>
            <tbody>
              {sales.map((s) => (
                <tr key={s.id}>
                  <td className="faint nowrap">{dateTime(s.createdAt)}</td>
                  <td>{s.label} <Plate plate={s.plate} /></td>
                  <td className="hide-mobile">{s.buyerName}</td>
                  <td className="hide-mobile">{s.sellerName || '-'}{s.commission > 0 && <span className="faint"> · {money(s.commission)}</span>}</td>
                  <td><span className="badge plain">{t(`channel_${s.channel}`)}</span> <span className="faint">{t(`method_${s.method}`)}</span></td>
                  <td className="num"><b>{money(s.price)}</b></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
      {pick && <PickVehicle onClose={() => setPick(false)} onPick={(v) => { setPick(false); setSellVehicle(v); }} />}
      {sellVehicle && <SellModal vehicle={sellVehicle} onClose={() => setSellVehicle(null)} onDone={() => { setSellVehicle(null); window.setTimeout(() => void load(), 4000); }} />}
    </div>
  );
}
