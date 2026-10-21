import React, { useCallback, useEffect, useState } from 'react';
import { ArrowDownTrayIcon, ArrowUpTrayIcon, BuildingLibraryIcon } from '@heroicons/react/24/outline';
import { useApp } from '../context';
import { t } from '../../lib/i18n';
import { money, dateTime } from '../../lib/format';
import type { LedgerEntry } from '../../lib/types';
import { Empty, Field, ListSkeleton, Modal, NumberInput } from '../../components/ui';
import { Kpi } from '../../components/vs';

export function AccountView() {
  const { call, session } = useApp();
  const [data, setData] = useState<{ balance: number; entries: LedgerEntry[] } | null>(null);
  const [mode, setMode] = useState<'deposit' | 'withdraw' | null>(null);
  const [amount, setAmount] = useState<number | undefined>();

  const load = useCallback(async () => {
    const d = await call<{ balance: number; entries: LedgerEntry[] }>('account.ledger', { limit: 150 });
    if (d) setData(d);
  }, [call]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!data) return <ListSkeleton rows={6} />;
  const income = data.entries.filter((e) => e.amount > 0).reduce((s, e) => s + e.amount, 0);
  const spend = data.entries.filter((e) => e.amount < 0).reduce((s, e) => s + e.amount, 0);

  return (
    <div className="stack s20">
      <div className="kpis">
        <Kpi label={t('ui_balance')} value={money(data.balance)} icon={BuildingLibraryIcon} />
        <Kpi label={t('ui_income')} value={money(income)} sub={t('ui_last_entries')} icon={ArrowDownTrayIcon} />
        <Kpi label={t('ui_spending')} value={money(spend)} sub={t('ui_last_entries')} icon={ArrowUpTrayIcon} />
        <div className="card kpi" style={{ justifyContent: 'center', gap: 8 }}>
          {session.flags.accountManage ? (
            <>
              <button className="btn primary" onClick={() => { setAmount(undefined); setMode('deposit'); }}><ArrowDownTrayIcon />{t('account_deposit')}</button>
              <button className="btn" onClick={() => { setAmount(undefined); setMode('withdraw'); }}><ArrowUpTrayIcon />{t('account_withdraw')}</button>
            </>
          ) : <span className="faint">{t('ui_account_readonly')}</span>}
        </div>
      </div>
      <div className="card">
        {data.entries.length === 0 ? <Empty title={t('ui_no_entries')} /> : (
          <table className="table">
            <thead><tr><th>{t('ui_date')}</th><th>{t('ui_booking')}</th><th className="hide-mobile">{t('ui_by')}</th><th className="num">{t('amount')}</th><th className="num hide-mobile">{t('ui_balance')}</th></tr></thead>
            <tbody>
              {data.entries.map((e) => (
                <tr key={e.id}>
                  <td className="faint nowrap">{dateTime(e.createdAt)}</td>
                  <td><span className="badge plain">{t(`ledger_${e.kind}`)}</span> <span className="muted">{e.text}</span></td>
                  <td className="hide-mobile faint">{e.actor || '-'}</td>
                  <td className="num" style={{ color: e.amount >= 0 ? 'var(--ok)' : 'var(--danger)' }}>{e.amount >= 0 ? '+' : ''}{money(e.amount)}</td>
                  <td className="num hide-mobile faint">{money(e.balanceAfter)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
      {mode && (
        <Modal title={mode === 'deposit' ? t('account_deposit') : t('account_withdraw')} size="narrow" onClose={() => setMode(null)}
          footer={<>
            <button className="btn ghost" onClick={() => setMode(null)}>{t('ui_cancel')}</button>
            <button className="btn primary" disabled={!amount} onClick={async () => {
              if (await call(mode === 'deposit' ? 'account.deposit' : 'account.withdraw', { amount }, t('ui_saved'))) {
                setMode(null);
                void load();
              }
            }}>{t('ui_confirm')}</button>
          </>}>
          <Field label={t('amount')} hint={mode === 'deposit' ? t('ui_deposit_hint') : t('ui_withdraw_hint')}>
            <NumberInput value={amount} onChange={setAmount} />
          </Field>
        </Modal>
      )}
    </div>
  );
}
