import React, { useCallback, useEffect, useState } from 'react';
import { TruckIcon, XCircleIcon, ArrowUturnLeftIcon, ClipboardDocumentListIcon, NoSymbolIcon } from '@heroicons/react/24/outline';
import { useApp } from '../context';
import { t } from '../../lib/i18n';
import { money, dateTime, relative } from '../../lib/format';
import type { Contract, StockItem } from '../../lib/types';
import { Confirm, Empty, Field, ListSkeleton, Modal, NumberInput, Plate, Segmented } from '../../components/ui';
import { Countdown, StatusBadge, TypeBadge } from '../../components/vs';

function ContractModal(props: { vehicle: StockItem; onClose: () => void; onDone: () => void }) {
  const { call } = useApp();
  const [reward, setReward] = useState<number | undefined>();
  const [note, setNote] = useState('');
  useEffect(() => {
    void call<{ reward: number }>('contracts.suggest', { stockId: props.vehicle.id }).then((d) => d && setReward(d.reward));
  }, [call, props.vehicle.id]);
  return (
    <Modal title={t('action_contract')} size="narrow" onClose={props.onClose}
      footer={<>
        <button className="btn ghost" onClick={props.onClose}>{t('ui_cancel')}</button>
        <button className="btn primary" disabled={!reward} onClick={async () => {
          if (await call('contracts.create', { stockId: props.vehicle.id, reward, note }, t('contract_created'))) props.onDone();
        }}>{t('ui_publish')}</button>
      </>}>
      <div className="stack">
        <div className="notice neutral">{t('ui_contract_info')}</div>
        <Field label={t('contract_reward')} hint={t('ui_contract_reward_hint')}>
          <NumberInput value={reward} onChange={setReward} />
        </Field>
        <Field label={t('contract_note')}>
          <input className="input" value={note} maxLength={255} onChange={(e) => setNote(e.target.value)} />
        </Field>
      </div>
    </Modal>
  );
}

type Tab = 'incoming' | 'contracts';

export function DeliveriesView() {
  const { call, session } = useApp();
  const f = session.flags;
  const [tab, setTab] = useState<Tab>('incoming');
  const [list, setList] = useState<StockItem[] | null>(null);
  const [contracts, setContracts] = useState<Contract[] | null>(null);
  const [history, setHistory] = useState(false);
  const [contractFor, setContractFor] = useState<StockItem | null>(null);
  const [confirm, setConfirm] = useState<{ kind: 'cancel' | 'recall' | 'cancelContract'; id: number } | null>(null);

  const load = useCallback(async () => {
    const [stock, cs] = await Promise.all([
      call<StockItem[]>('stock.list', { statuses: ['transit', 'waiting', 'pickup'] }),
      call<Contract[]>('contracts.list', { history }),
    ]);
    setList(stock || []);
    setContracts(cs || []);
  }, [call, history]);

  useEffect(() => {
    void load();
    const id = window.setInterval(() => void load(), 30000);
    return () => window.clearInterval(id);
  }, [load]);

  const transit = (list || []).filter((v) => v.status === 'transit').sort((a, b) => a.eta - b.eta);
  const waiting = (list || []).filter((v) => v.status === 'waiting' || v.status === 'pickup');

  const runConfirm = async () => {
    if (!confirm) return;
    if (confirm.kind === 'cancel') await call('stock.cancelOrder', { stockId: confirm.id }, t('ui_saved'));
    if (confirm.kind === 'recall') await call('stock.recall', { stockId: confirm.id }, t('ui_saved'));
    if (confirm.kind === 'cancelContract') await call('contracts.cancel', { contractId: confirm.id }, t('contract_cancelled'));
    setConfirm(null);
    void load();
  };

  return (
    <div className="stack">
      <div className="toolbar">
        <Segmented<Tab> value={tab} onChange={setTab} options={[
          { value: 'incoming', label: t('ui_incoming'), count: (list || []).length },
          { value: 'contracts', label: t('menu_contracts'), count: (contracts || []).filter((c) => c.status === 'open' || c.status === 'taken').length },
        ]} />
      </div>
      {!list || !contracts ? <ListSkeleton rows={6} /> : tab === 'incoming' ? (
        <div className="grid c2">
          <div className="card">
            <div className="card-head"><TruckIcon style={{ width: 18 }} /><div className="h2">{t('ui_in_transit')}</div><span className="faint">{transit.length}</span></div>
            {transit.length === 0 ? <Empty title={t('ui_no_transit')} /> : transit.map((v) => (
              <div key={v.id} className="list-item" style={{ cursor: 'default' }}>
                <TypeBadge type={v.vtype} />
                <div className="flex1">
                  <div className="h3">{v.label}</div>
                  <div className="faint" style={{ fontSize: 12 }}>{v.deliveryLabel} · {v.orderedBy}</div>
                  {v.note && <div className="faint" style={{ fontSize: 12 }}>{v.note}</div>}
                </div>
                <Countdown to={v.eta} />
                {f.order && <button className="icon-btn danger" title={t('action_cancel_order')} onClick={() => setConfirm({ kind: 'cancel', id: v.id })}><XCircleIcon /></button>}
              </div>
            ))}
          </div>
          <div className="card">
            <div className="card-head"><ClipboardDocumentListIcon style={{ width: 18 }} /><div className="h2">{t('ui_ready_for_pickup')}</div><span className="faint">{waiting.length}</span></div>
            {waiting.length === 0 ? <Empty title={t('ui_no_waiting')} /> : waiting.map((v) => (
              <div key={v.id} className="list-item" style={{ cursor: 'default', alignItems: 'flex-start' }}>
                <TypeBadge type={v.vtype} />
                <div className="flex1 stack s8" style={{ gap: 4 }}>
                  <div className="row"><b className="flex1">{v.label}</b><StatusBadge status={v.status} /></div>
                  <div className="row"><Plate plate={v.plate} /><span className="faint" style={{ fontSize: 12 }}>{v.deliveryLabel} · {relative(v.arrivedAt)}</span></div>
                  {v.contract && (
                    <span className="faint" style={{ fontSize: 12 }}>
                      {v.contract.status === 'taken' ? t('contract_taken_by', v.contract.takerName || '-') : t('ui_contract_published', money(v.contract.reward))}
                    </span>
                  )}
                  <div className="row wrap">
                    {f.contracts && session.meta.contractsEnabled && v.status === 'waiting' && !v.contract && (
                      <button className="btn sm" onClick={() => setContractFor(v)}>{t('action_contract')}</button>
                    )}
                    {f.stockManage && v.status === 'pickup' && (
                      <button className="btn sm" onClick={() => setConfirm({ kind: 'recall', id: v.id })}><ArrowUturnLeftIcon />{t('action_recall')}</button>
                    )}
                  </div>
                </div>
              </div>
            ))}
            <div className="card-body"><div className="notice neutral">{t('ui_pickup_hint')}</div></div>
          </div>
        </div>
      ) : (
        <div className="card">
          <div className="card-head">
            <div className="h2">{t('menu_contracts')}</div>
            <button className={`chip ${history ? 'on' : ''}`} onClick={() => setHistory((h) => !h)}>{t('ui_show_history')}</button>
          </div>
          {contracts.length === 0 ? <Empty title={t('ui_no_contracts')} /> : (
            <table className="table">
              <thead><tr><th>{t('ui_vehicle')}</th><th>{t('ui_status')}</th><th>{t('ui_taker')}</th><th className="num">{t('contract_reward')}</th><th>{t('ui_date')}</th><th /></tr></thead>
              <tbody>
                {contracts.map((c) => (
                  <tr key={c.id}>
                    <td>{c.vehicle?.label || '-'} <span className="faint">{c.vehicle?.plate}</span></td>
                    <td><span className={`badge ${c.status === 'done' ? 'ok' : c.status === 'failed' ? 'danger' : c.status === 'taken' ? 'accent' : ''}`}>{t(`status_contract_${c.status}`)}</span></td>
                    <td>{c.takerName || '-'}{c.status === 'taken' && c.deadlineAt > 0 && <> · <Countdown to={c.deadlineAt} /></>}</td>
                    <td className="num">{money(c.reward)}{c.payout > 0 && c.payout !== c.reward && <div className="faint" style={{ fontSize: 11.5 }}>{t('ui_paid_out', money(c.payout))}</div>}</td>
                    <td className="faint">{dateTime(c.createdAt)}</td>
                    <td className="right">{f.contracts && c.status === 'open' && <button className="icon-btn danger" title={t('contract_cancel')} onClick={() => setConfirm({ kind: 'cancelContract', id: c.id })}><NoSymbolIcon /></button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}
      {contractFor && <ContractModal vehicle={contractFor} onClose={() => setContractFor(null)} onDone={() => { setContractFor(null); void load(); }} />}
      {confirm && (
        <Confirm
          title={confirm.kind === 'cancel' ? t('action_cancel_order') : confirm.kind === 'recall' ? t('action_recall') : t('contract_cancel')}
          text={confirm.kind === 'cancel' ? t('ui_cancel_order_text', session.meta.cancelFeePercent) : confirm.kind === 'recall' ? t('action_recall_desc') : t('contract_cancel_text')}
          danger
          onCancel={() => setConfirm(null)}
          onConfirm={() => void runConfirm()}
        />
      )}
    </div>
  );
}
