import React, { useCallback, useEffect, useState } from 'react';
import { ArrowPathIcon, CheckIcon, XMarkIcon } from '@heroicons/react/24/outline';
import { useApp } from '../context';
import { t } from '../../lib/i18n';
import { money, relative } from '../../lib/format';
import type { TradeIn } from '../../lib/types';
import { Empty, Field, ListSkeleton, Modal, NumberInput, Plate } from '../../components/ui';
import { ConditionMeter, Countdown, TypeBadge } from '../../components/vs';

function OfferModal(props: { trade: TradeIn; onClose: () => void; onDone: () => void }) {
  const { call } = useApp();
  const tr = props.trade;
  const [amount, setAmount] = useState<number | undefined>(tr.asking > 0 ? tr.asking : tr.suggestion ?? undefined);
  return (
    <Modal title={t('tradein_make_offer')} size="narrow" onClose={props.onClose}
      footer={<>
        <button className="btn ghost" onClick={props.onClose}>{t('ui_cancel')}</button>
        <button className="btn primary" disabled={!amount} onClick={async () => {
          if (await call('tradeins.offer', { tradeId: tr.id, amount }, t('tradein_offer_sent'))) props.onDone();
        }}><CheckIcon />{t('ui_send_offer')}</button>
      </>}>
      <div className="stack">
        <div className="kv">
          <span>{t('ui_vehicle')}</span><span>{tr.label}</span>
          <span>{t('ui_asking')}</span><span>{tr.asking > 0 ? money(tr.asking) : '-'}</span>
          <span>{t('ui_list')}</span><span>{tr.listPrice ? money(tr.listPrice) : '-'}</span>
          <span>{t('ui_suggestion')}</span><span>{tr.suggestion ? money(tr.suggestion) : '-'}</span>
          <span>{t('ui_damage')}</span><span>{tr.damage} %</span>
        </div>
        <Field label={t('tradein_offer_amount')} hint={t('ui_tradein_hint')}>
          <NumberInput value={amount} onChange={setAmount} />
        </Field>
      </div>
    </Modal>
  );
}

export function TradeInsView() {
  const { call } = useApp();
  const [list, setList] = useState<TradeIn[] | null>(null);
  const [offer, setOffer] = useState<TradeIn | null>(null);

  const load = useCallback(async () => {
    const d = await call<TradeIn[]>('tradeins.list');
    setList(d || []);
  }, [call]);

  useEffect(() => {
    void load();
    const id = window.setInterval(() => void load(), 15000);
    return () => window.clearInterval(id);
  }, [load]);

  if (!list) return <ListSkeleton rows={4} />;
  return (
    <div className="stack">
      <div className="toolbar">
        <span className="muted flex1">{t('ui_tradein_intro')}</span>
        <button className="btn sm" onClick={() => void load()}><ArrowPathIcon />{t('ui_refresh')}</button>
      </div>
      {list.length === 0 ? <Empty title={t('ui_no_tradeins')} text={t('ui_no_tradeins_text')} /> : (
        <div className="vgrid">
          {list.map((tr) => (
            <div key={tr.id} className="card vcard" style={{ cursor: 'default' }}>
              <div className="row">
                <TypeBadge type={tr.vtype} />
                <div className="flex1"><div className="vtitle ellipsis">{tr.label}</div><div className="faint" style={{ fontSize: 12 }}>{tr.sellerName} · {relative(tr.createdAt)}</div></div>
              </div>
              <div className="row between"><Plate plate={tr.plate} /><span className="faint">{t('ui_asking')}: <b>{tr.asking > 0 ? money(tr.asking) : '-'}</b></span></div>
              <ConditionMeter condition={tr.condition} />
              <div className="row between faint" style={{ fontSize: 12 }}>
                <span>{tr.status === 'offered' ? t('ui_offer_sent', money(tr.offer)) : t('ui_expires')}</span>
                <Countdown to={tr.expiresAt} />
              </div>
              {tr.status === 'open' && (
                <div className="row">
                  <button className="btn sm primary flex1" onClick={() => setOffer(tr)}><CheckIcon />{t('tradein_make_offer')}</button>
                  <button className="btn sm danger" onClick={async () => { if (await call('tradeins.decline', { tradeId: tr.id }, t('ui_saved'))) void load(); }}><XMarkIcon /></button>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
      {offer && <OfferModal trade={offer} onClose={() => setOffer(null)} onDone={() => { setOffer(null); void load(); }} />}
    </div>
  );
}
