import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { MagnifyingGlassIcon, PlusIcon, MinusIcon, TrashIcon, ShoppingCartIcon } from '@heroicons/react/24/outline';
import { useApp } from '../context';
import { t } from '../../lib/i18n';
import { money } from '../../lib/format';
import type { CatalogEntry, VehicleType } from '../../lib/types';
import { Confirm, Empty, ListSkeleton, NumberInput, useDebounced } from '../../components/ui';
import { minutesText, TypeBadge } from '../../components/vs';

interface CartLine { entry: CatalogEntry; quantity: number; price: number; point: string }

export function OrderView() {
  const { call, session, go } = useApp();
  const [catalog, setCatalog] = useState<CatalogEntry[] | null>(null);
  const [query, setQuery] = useState('');
  const q = useDebounced(query, 200).toLowerCase();
  const [category, setCategory] = useState('');
  const [vtype, setVtype] = useState<VehicleType | ''>('');
  const [cart, setCart] = useState<CartLine[]>([]);
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const d = await call<CatalogEntry[]>('catalog.list');
    setCatalog(d || []);
  }, [call]);

  useEffect(() => {
    void load();
  }, [load]);

  const filtered = useMemo(() => (catalog || []).filter((e) =>
    (!q || e.label.toLowerCase().includes(q) || e.model.includes(q) || (e.brand || '').toLowerCase().includes(q)) &&
    (!category || e.category === category) && (!vtype || e.vtype === vtype)), [catalog, q, category, vtype]);

  const categories = useMemo(() => session.meta.categories.filter((c) => (catalog || []).some((e) => e.category === c)), [catalog, session.meta.categories]);
  const types = useMemo(() => session.meta.types.filter((ty) => (catalog || []).some((e) => e.vtype === ty)), [catalog, session.meta.types]);
  const total = cart.reduce((s, l) => s + (l.entry.wholesale || 0) * l.quantity, 0);
  const pointLabel = (id: string) => session.meta.points.find((p) => p.id === id)?.label || id;

  const add = (e: CatalogEntry) => {
    if (!e.points || e.points.length === 0) return;
    setCart((c) => {
      const existing = c.find((l) => l.entry.model === e.model);
      if (existing) return c.map((l) => (l === existing ? { ...l, quantity: Math.min(20, l.quantity + 1) } : l));
      return [...c, { entry: e, quantity: 1, price: e.price, point: e.points![0] }];
    });
  };

  const submit = async () => {
    setBusy(true);
    let ok = 0;
    for (const l of cart) {
      const res = await call('orders.create', { order: { model: l.entry.model, quantity: l.quantity, price: l.price, deliveryPoint: l.point } });
      if (res) ok += 1;
      else break;
    }
    setBusy(false);
    setConfirm(false);
    if (ok === cart.length) {
      setCart([]);
      go({ name: 'deliveries' });
    } else {
      setCart((c) => c.slice(ok));
    }
  };

  if (!catalog) return <ListSkeleton rows={8} />;

  return (
    <div className="grid order-layout">
      <div className="stack">
        <div className="toolbar">
          <div className="input-wrap">
            <MagnifyingGlassIcon />
            <input className="input" placeholder={t('ui_search_catalog')} value={query} onChange={(e) => setQuery(e.target.value)} />
          </div>
          <select className="select" style={{ width: 170 }} value={category} onChange={(e) => setCategory(e.target.value)}>
            <option value="">{t('ui_all_categories')}</option>
            {categories.map((c) => <option key={c} value={c}>{t(`category_${c}`)}</option>)}
          </select>
          <select className="select" style={{ width: 150 }} value={vtype} onChange={(e) => setVtype(e.target.value as VehicleType | '')}>
            <option value="">{t('ui_all_types')}</option>
            {types.map((ty) => <option key={ty} value={ty}>{t(`vtype_${ty}`)}</option>)}
          </select>
        </div>
        {filtered.length === 0 ? <Empty title={t('ui_catalog_empty')} /> : (
          <div className="vgrid">
            {filtered.map((e) => {
              const deliverable = (e.points || []).length > 0;
              return (
                <div key={e.model} className="card vcard" onClick={() => add(e)} style={{ opacity: deliverable ? 1 : 0.5 }}>
                  <div className="row">
                    <TypeBadge type={e.vtype} />
                    <div className="flex1" style={{ minWidth: 0 }}>
                      <div className="vtitle ellipsis">{e.label}</div>
                      <div className="faint ellipsis" style={{ fontSize: 12 }}>{e.brand || t(`category_${e.category}`)}</div>
                    </div>
                  </div>
                  <div className="row between">
                    <span className="faint" style={{ fontSize: 12 }}>{t('ui_wholesale')}</span>
                    <span className="vprice">{money(e.wholesale)}</span>
                  </div>
                  <div className="row between faint" style={{ fontSize: 12 }}>
                    <span>{t('ui_list_price', money(e.price))}</span>
                    <span>{deliverable ? minutesText(e.minutes) : t('err_no_delivery_point')}</span>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
      <div className="card cart">
        <div className="card-head"><ShoppingCartIcon style={{ width: 18 }} /><div className="h2">{t('ui_cart')}</div></div>
        {cart.length === 0 ? <Empty title={t('ui_cart_empty')} text={t('ui_cart_empty_text')} /> : (
          <div className="card-body stack">
            {cart.map((l, i) => (
              <div key={l.entry.model} className="stack s8" style={{ borderBottom: '1px solid var(--border)', paddingBottom: 12 }}>
                <div className="row">
                  <b className="flex1 ellipsis">{l.entry.label}</b>
                  <button className="icon-btn" onClick={() => setCart((c) => c.map((x, j) => (j === i ? { ...x, quantity: Math.max(1, x.quantity - 1) } : x)))}><MinusIcon /></button>
                  <span style={{ minWidth: 18, textAlign: 'center' }}>{l.quantity}</span>
                  <button className="icon-btn" onClick={() => setCart((c) => c.map((x, j) => (j === i ? { ...x, quantity: Math.min(20, x.quantity + 1) } : x)))}><PlusIcon /></button>
                  <button className="icon-btn danger" onClick={() => setCart((c) => c.filter((_, j) => j !== i))}><TrashIcon /></button>
                </div>
                <div className="grid c2" style={{ gap: 8 }}>
                  <label className="field"><span className="label">{t('order_sale_price')}</span>
                    <NumberInput value={l.price} onChange={(v) => setCart((c) => c.map((x, j) => (j === i ? { ...x, price: v ?? 0 } : x)))} />
                  </label>
                  <label className="field"><span className="label">{t('order_point')}</span>
                    <select className="select" value={l.point} onChange={(e) => setCart((c) => c.map((x, j) => (j === i ? { ...x, point: e.target.value } : x)))}>
                      {(l.entry.points || []).map((p) => <option key={p} value={p}>{pointLabel(p)}</option>)}
                    </select>
                  </label>
                </div>
                <div className="row between faint" style={{ fontSize: 12 }}>
                  <span>{minutesText(l.entry.minutes)}</span>
                  <span>{money((l.entry.wholesale || 0) * l.quantity)}</span>
                </div>
              </div>
            ))}
            <div className="sum-line total"><span>{t('ui_total')}</span><span>{money(total)}</span></div>
            <button className="btn primary block" disabled={busy} onClick={() => setConfirm(true)}>{t('ui_order_now')}</button>
          </div>
        )}
      </div>
      {confirm && (
        <Confirm title={t('order_confirm_title')} text={t('ui_order_confirm', cart.reduce((s, l) => s + l.quantity, 0), money(total))}
          onCancel={() => setConfirm(false)} onConfirm={() => void submit()} />
      )}
    </div>
  );
}
