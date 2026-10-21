import React, { useCallback, useEffect, useState } from 'react';
import { useApp } from '../context';
import { t } from '../../lib/i18n';
import { money, dateTime, relative } from '../../lib/format';
import type { Finance } from '../../lib/types';
import { Confirm, Empty, ListSkeleton, Plate, Segmented } from '../../components/ui';

type Filter = 'open' | 'defaulted' | 'all';

const TONE: Record<string, string> = { active: 'accent', paid: 'ok', defaulted: 'danger', repossessed: '' };

export function FinanceView() {
  const { call, session } = useApp();
  const [list, setList] = useState<Finance[] | null>(null);
  const [filter, setFilter] = useState<Filter>('open');
  const [repossess, setRepossess] = useState<Finance | null>(null);

  const load = useCallback(async () => {
    const d = await call<Finance[]>('finance.list');
    setList(d || []);
  }, [call]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!list) return <ListSkeleton rows={5} />;
  const shown = list.filter((f) => filter === 'all' || (filter === 'open' ? f.status === 'active' || f.status === 'defaulted' : f.status === 'defaulted'));
  const outstanding = list.filter((f) => f.status === 'active' || f.status === 'defaulted').reduce((s, f) => s + (f.total - f.paid), 0);

  return (
    <div className="stack">
      <div className="toolbar">
        <Segmented<Filter> value={filter} onChange={setFilter} options={[
          { value: 'open', label: t('ui_filter_running') },
          { value: 'defaulted', label: t('finance_status_defaulted'), count: list.filter((f) => f.status === 'defaulted').length },
          { value: 'all', label: t('ui_filter_all') },
        ]} />
        <span className="faint flex1 right">{t('ui_outstanding', money(outstanding))}</span>
      </div>
      <div className="notice neutral">{t('ui_finance_intro', session.settings.finance.downPaymentPercent, session.settings.finance.installments, session.settings.finance.interestPercent, session.meta.maxMissed)}</div>
      <div className="card">
        {shown.length === 0 ? <Empty title={t('ui_no_finances')} /> : (
          <table className="table">
            <thead><tr><th>{t('ui_vehicle')}</th><th>{t('ui_buyer')}</th><th>{t('ui_status')}</th><th className="num">{t('ui_paid')}</th><th className="num hide-mobile">{t('ui_rate')}</th><th className="hide-mobile">{t('ui_next_due')}</th><th /></tr></thead>
            <tbody>
              {shown.map((f) => (
                <tr key={f.id}>
                  <td>{f.label} <Plate plate={f.plate} /></td>
                  <td>{f.buyerName}</td>
                  <td><span className={`badge ${TONE[f.status] || ''}`}>{t(`finance_status_${f.status}`)}</span>{f.missed > 0 && <span className="faint"> · {t('ui_missed', f.missed)}</span>}</td>
                  <td className="num">{money(f.paid)} <span className="faint">/ {money(f.total)}</span></td>
                  <td className="num hide-mobile">{money(f.rate)} <span className="faint">· {f.ratesLeft}x</span></td>
                  <td className="hide-mobile faint" title={dateTime(f.nextDueAt)}>{f.status === 'active' || f.status === 'defaulted' ? relative(f.nextDueAt) : '-'}</td>
                  <td className="right">{f.status === 'defaulted' && <button className="btn sm danger" onClick={() => setRepossess(f)}>{t('finance_repossess')}</button>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
      {repossess && (
        <Confirm title={t('finance_repossess')} text={t('finance_repossess_text', repossess.label || '')} danger
          onCancel={() => setRepossess(null)}
          onConfirm={async () => {
            if (await call('finance.repossess', { financeId: repossess.id }, t('finance_repossessed'))) void load();
            setRepossess(null);
          }} />
      )}
    </div>
  );
}
