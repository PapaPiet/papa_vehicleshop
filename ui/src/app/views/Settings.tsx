import React, { useState } from 'react';
import { useApp } from '../context';
import { t } from '../../lib/i18n';
import type { ShopSettings } from '../../lib/types';
import { Field, NumberInput, Toggle } from '../../components/ui';

export function SettingsView() {
  const { call, session, reloadSession } = useApp();
  const [s, setS] = useState<ShopSettings>(JSON.parse(JSON.stringify(session.settings)));
  const set = <K extends keyof ShopSettings>(key: K, value: ShopSettings[K]) => setS((x) => ({ ...x, [key]: value }));

  const save = async () => {
    const res = await call('settings.save', {
      settings: {
        commissionPercent: s.commissionPercent,
        maxDiscountPercent: s.maxDiscountPercent,
        description: s.description,
        testDrive: s.testDrive,
        finance: s.finance,
        tradeIn: { enabled: s.tradeIn.enabled },
        deliveryPoints: s.deliveryPoints,
      },
    }, t('ui_saved'));
    if (res) await reloadSession();
  };

  return (
    <div className="stack s20" style={{ maxWidth: 820 }}>
      <div className="notice neutral">{t('ui_settings_intro')}</div>
      <div className="card">
        <div className="card-head"><div className="h2">{t('ui_sales_rules')}</div></div>
        <div className="card-body grid c2">
          <Field label={t('set_commissionPercent')} hint={t('ui_commission_hint')}><NumberInput value={s.commissionPercent} onChange={(v) => set('commissionPercent', v ?? 0)} /></Field>
          <Field label={t('set_maxDiscountPercent')} hint={t('ui_discount_rule_hint')}><NumberInput value={s.maxDiscountPercent} onChange={(v) => set('maxDiscountPercent', v ?? 0)} /></Field>
          <Field label={t('ui_description')} className="span-all"><textarea className="textarea" value={s.description} maxLength={500} onChange={(e) => set('description', e.target.value)} /></Field>
        </div>
      </div>
      <div className="card">
        <div className="card-head"><div className="h2">{t('menu_testdrive')}</div><Toggle checked={s.testDrive.enabled} onChange={(v) => set('testDrive', { ...s.testDrive, enabled: v })} /></div>
        <div className="card-body grid c2">
          <Field label={t('set_testDriveSeconds')}><NumberInput value={s.testDrive.seconds} onChange={(v) => set('testDrive', { ...s.testDrive, seconds: v ?? 180 })} disabled={!s.testDrive.enabled} /></Field>
          <Field label={t('set_testDriveDeposit')}><NumberInput value={s.testDrive.deposit} onChange={(v) => set('testDrive', { ...s.testDrive, deposit: v ?? 0 })} disabled={!s.testDrive.enabled} /></Field>
        </div>
      </div>
      <div className="card">
        <div className="card-head"><div className="h2">{t('finance_title')}</div><Toggle checked={s.finance.enabled} onChange={(v) => set('finance', { ...s.finance, enabled: v })} /></div>
        <div className="card-body grid c2">
          <Field label={t('ui_down_payment_percent')}><NumberInput value={s.finance.downPaymentPercent} onChange={(v) => set('finance', { ...s.finance, downPaymentPercent: v ?? 0 })} disabled={!s.finance.enabled} /></Field>
          <Field label={t('ui_installments')}><NumberInput value={s.finance.installments} onChange={(v) => set('finance', { ...s.finance, installments: v ?? 2 })} disabled={!s.finance.enabled} /></Field>
          <Field label={t('ui_interval_minutes')} hint={t('ui_interval_hint')}><NumberInput value={s.finance.intervalMinutes} onChange={(v) => set('finance', { ...s.finance, intervalMinutes: v ?? 60 })} disabled={!s.finance.enabled} /></Field>
          <Field label={t('ui_interest_percent')}><NumberInput value={s.finance.interestPercent} onChange={(v) => set('finance', { ...s.finance, interestPercent: v ?? 0 })} disabled={!s.finance.enabled} /></Field>
        </div>
      </div>
      <div className="card">
        <div className="card-head"><div className="h2">{t('nav_tradeins')}</div><Toggle checked={s.tradeIn.enabled} onChange={(v) => set('tradeIn', { ...s.tradeIn, enabled: v })} /></div>
        <div className="card-body"><span className="faint">{t('ui_tradein_settings_hint')}</span></div>
      </div>
      <div className="card">
        <div className="card-head"><div className="h2">{t('ui_delivery_points')}</div></div>
        <div className="card-body stack s8">
          <span className="faint" style={{ fontSize: 12 }}>{t('ui_delivery_points_hint')}</span>
          <div className="chips">
            {session.meta.points.filter((p) => p.enabled).map((p) => {
              const on = s.deliveryPoints.length === 0 || s.deliveryPoints.includes(p.id);
              return (
                <button key={p.id} className={`chip ${on ? 'on' : ''}`} onClick={() => {
                  const all = session.meta.points.filter((x) => x.enabled).map((x) => x.id);
                  const current = s.deliveryPoints.length === 0 ? all : s.deliveryPoints;
                  const next = on ? current.filter((x) => x !== p.id) : [...current, p.id];
                  set('deliveryPoints', next.length === all.length ? [] : next);
                }}>{p.label}</button>
              );
            })}
          </div>
        </div>
      </div>
      <div className="row"><div className="flex1" /><button className="btn primary" onClick={() => void save()}>{t('ui_save')}</button></div>
    </div>
  );
}
