import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  MagnifyingGlassIcon,
  TagIcon,
  RectangleGroupIcon,
  ArchiveBoxArrowDownIcon,
  HandRaisedIcon,
  BookmarkIcon,
  ArrowUturnLeftIcon,
  TrashIcon,
  ArrowRightStartOnRectangleIcon,
  MapPinIcon,
} from '@heroicons/react/24/outline';
import { useApp } from '../context';
import { t } from '../../lib/i18n';
import { money, dateTime, relative } from '../../lib/format';
import type { DisplaySpot, NearbyPlayer, StockDetail, StockItem, StockStatus } from '../../lib/types';
import { Confirm, Empty, Field, ListSkeleton, Modal, NumberInput, Plate, Segmented, Toggle, useDebounced } from '../../components/ui';
import { ConditionMeter, Drawer, StatusBadge, TypeBadge } from '../../components/vs';

type Filter = 'all' | 'storage' | 'display' | 'out';

const FILTERS: Record<Filter, StockStatus[]> = {
  all: ['storage', 'display', 'out', 'testdrive', 'pickup', 'waiting'],
  storage: ['storage'],
  display: ['display', 'testdrive'],
  out: ['out', 'pickup'],
};

/** Picks a player near the actor (server-side positions). */
export function NearbyPicker(props: { value?: number | null; onChange: (src: number | null, name?: string) => void }) {
  const { call } = useApp();
  const [list, setList] = useState<NearbyPlayer[] | null>(null);
  const load = useCallback(async () => {
    const d = await call<NearbyPlayer[]>('players.nearby');
    setList(d || []);
  }, [call]);
  useEffect(() => {
    void load();
  }, [load]);
  if (!list) return <ListSkeleton rows={2} />;
  if (list.length === 0) {
    return (
      <div className="notice neutral">
        <span className="flex1">{t('ui_no_players_nearby')}</span>
        <button className="btn sm" onClick={() => void load()}>{t('ui_refresh')}</button>
      </div>
    );
  }
  return (
    <div className="chips">
      {list.map((p) => (
        <button key={p.src} className={`chip ${props.value === p.src ? 'on' : ''}`} onClick={() => props.onChange(p.src, p.name)}>
          {p.name} <span className="faint">{p.distance} m</span>
        </button>
      ))}
    </div>
  );
}

export function SellModal(props: { vehicle: StockItem; onClose: () => void; onDone: () => void }) {
  const { call, session } = useApp();
  const v = props.vehicle;
  const [target, setTarget] = useState<number | null>(null);
  const [price, setPrice] = useState<number | undefined>(v.price);
  const [finance, setFinance] = useState(true);
  const maxDiscount = session.settings.maxDiscountPercent;
  const discount = v.price > 0 && price !== undefined ? Math.max(0, Math.round(((v.price - price) / v.price) * 1000) / 10) : 0;
  const tooHigh = discount > maxDiscount && !session.flags.boss;
  return (
    <Modal
      title={t('ui_sell_title', v.label)}
      onClose={props.onClose}
      footer={
        <>
          <button className="btn ghost" onClick={props.onClose}>{t('ui_cancel')}</button>
          <button
            className="btn primary"
            disabled={!target || !price || tooHigh}
            onClick={async () => {
              const res = await call<{ customer: string }>('sell.offer', { offer: { stockId: v.id, targetSrc: target, price, allowFinance: finance } });
              if (res) {
                props.onDone();
              }
            }}
          >
            <HandRaisedIcon /> {t('ui_send_offer')}
          </button>
        </>
      }
    >
      <div className="stack">
        <Field label={t('ui_customer')} hint={t('ui_customer_hint')}>
          <NearbyPicker value={target} onChange={(src) => setTarget(src)} />
        </Field>
        <div className="grid c2">
          <Field label={t('ui_price')} hint={discount > 0 ? t('ui_discount_hint', discount, maxDiscount) : t('ui_list_price', money(v.price))}>
            <NumberInput value={price} onChange={setPrice} />
          </Field>
          <Field label={t('ui_finance_allowed')}>
            <Toggle checked={finance} onChange={setFinance} label={session.settings.finance.enabled ? t('ui_yes') : t('ui_finance_disabled')} disabled={!session.settings.finance.enabled} />
          </Field>
        </div>
        {tooHigh && <div className="notice danger">{t('err_discount_too_high')}</div>}
        <div className="notice neutral">{t('ui_offer_info', session.settings.commissionPercent)}</div>
      </div>
    </Modal>
  );
}

function PriceModal(props: { vehicle: StockItem; onClose: () => void; onDone: () => void }) {
  const { call } = useApp();
  const [price, setPrice] = useState<number | undefined>(props.vehicle.price);
  const [note, setNote] = useState(props.vehicle.note || '');
  return (
    <Modal
      title={t('action_price')}
      size="narrow"
      onClose={props.onClose}
      footer={
        <>
          <button className="btn ghost" onClick={props.onClose}>{t('ui_cancel')}</button>
          <button className="btn primary" onClick={async () => {
            if (await call('stock.price', { stockId: props.vehicle.id, price: price ?? 0, note }, t('ui_saved'))) props.onDone();
          }}>{t('ui_save')}</button>
        </>
      }
    >
      <div className="stack">
        <Field label={t('ui_price')} hint={props.vehicle.listPrice ? t('ui_list_price', money(props.vehicle.listPrice)) : undefined}>
          <NumberInput value={price} onChange={setPrice} />
        </Field>
        <Field label={t('stock_note')} hint={t('ui_note_hint')}>
          <input className="input" value={note} maxLength={255} onChange={(e) => setNote(e.target.value)} />
        </Field>
      </div>
    </Modal>
  );
}

function DisplayPickModal(props: { vehicle: StockItem; onClose: () => void; onDone: () => void }) {
  const { call } = useApp();
  const [spots, setSpots] = useState<DisplaySpot[] | null>(null);
  useEffect(() => {
    void call<DisplaySpot[]>('displays.list').then((d) => setSpots(d || []));
  }, [call]);
  return (
    <Modal title={t('menu_choose_display')} onClose={props.onClose}>
      {!spots ? <ListSkeleton rows={3} /> : (
        <div className="spots">
          {spots.filter((s) => s.kind === 'stock').map((s) => {
            const allowed = s.types.includes(props.vehicle.vtype);
            const free = !s.vehicle;
            return (
              <button key={s.id} className={`spot ${free ? '' : 'taken'}`} disabled={!free || !allowed}
                style={{ cursor: free && allowed ? 'pointer' : 'not-allowed', opacity: free && allowed ? 1 : 0.5, textAlign: 'left', color: 'inherit' }}
                onClick={async () => {
                  if (await call('stock.display', { stockId: props.vehicle.id, displayId: s.id }, t('ui_saved'))) props.onDone();
                }}>
                <b>{s.label || t('display_number', s.id)}</b>
                <span className="faint" style={{ fontSize: 12 }}>
                  {free ? (allowed ? t('display_free') : t('display_wrong_type')) : t('display_taken', s.vehicle?.label || '')}
                </span>
                <div className="types">{s.types.map((ty) => <span key={ty} className="pill">{t(`vtype_${ty}`)}</span>)}</div>
              </button>
            );
          })}
        </div>
      )}
    </Modal>
  );
}

function ReserveModal(props: { vehicle: StockItem; onClose: () => void; onDone: () => void }) {
  const { call } = useApp();
  const [target, setTarget] = useState<number | null>(null);
  return (
    <Modal title={t('action_reserve')} size="narrow" onClose={props.onClose}
      footer={<>
        <button className="btn ghost" onClick={props.onClose}>{t('ui_cancel')}</button>
        <button className="btn primary" disabled={!target} onClick={async () => {
          if (await call('stock.reserve', { stockId: props.vehicle.id, targetSrc: target }, t('ui_saved'))) props.onDone();
        }}>{t('action_reserve')}</button>
      </>}>
      <Field label={t('ui_customer')} hint={t('ui_reserve_hint')}>
        <NearbyPicker value={target} onChange={(src) => setTarget(src)} />
      </Field>
    </Modal>
  );
}

function VehicleDrawer(props: { id: number; onClose: () => void; onChanged: () => void }) {
  const { call, session } = useApp();
  const f = session.flags;
  const [v, setV] = useState<StockDetail | null>(null);
  const [modal, setModal] = useState<'price' | 'display' | 'sell' | 'reserve' | 'release' | 'scrap' | 'recall' | null>(null);
  const load = useCallback(async () => {
    const d = await call<StockDetail>('stock.get', { stockId: props.id });
    if (d) setV(d);
  }, [call, props.id]);
  useEffect(() => {
    void load();
  }, [load]);
  const done = () => {
    setModal(null);
    void load();
    props.onChanged();
  };
  if (!v) return <Drawer title="..." onClose={props.onClose}><ListSkeleton rows={4} /></Drawer>;
  const inShop = v.status === 'storage' || v.status === 'display';
  return (
    <Drawer
      title={v.label}
      icon={<TypeBadge type={v.vtype} />}
      onClose={props.onClose}
      footer={
        <>
          {f.priceEdit && v.status !== 'transit' && <button className="btn sm" onClick={() => setModal('price')}><TagIcon />{t('action_price')}</button>}
          {f.displayManage && v.status === 'storage' && <button className="btn sm" onClick={() => setModal('display')}><RectangleGroupIcon />{t('action_display')}</button>}
          {f.displayManage && v.status === 'display' && (
            <button className="btn sm" onClick={async () => { if (await call('stock.undisplay', { stockId: v.id }, t('ui_saved'))) done(); }}>
              <ArchiveBoxArrowDownIcon />{t('action_undisplay')}
            </button>
          )}
          {f.sell && inShop && <button className="btn sm primary" onClick={() => setModal('sell')}><HandRaisedIcon />{t('action_sell')}</button>}
          {f.sell && inShop && (v.reservedFor
            ? <button className="btn sm" onClick={async () => { if (await call('stock.reserve', { stockId: v.id }, t('ui_saved'))) done(); }}><BookmarkIcon />{t('action_unreserve')}</button>
            : <button className="btn sm" onClick={() => setModal('reserve')}><BookmarkIcon />{t('action_reserve')}</button>)}
          {f.stockManage && (v.status === 'out' || v.status === 'pickup') && <button className="btn sm" onClick={() => setModal('recall')}><ArrowUturnLeftIcon />{t('action_recall')}</button>}
          {f.boss && (inShop || v.status === 'out') && <button className="btn sm ghost" onClick={() => setModal('release')}><ArrowRightStartOnRectangleIcon />{t('action_release')}</button>}
          {f.boss && (inShop || v.status === 'out') && <button className="btn sm danger" onClick={() => setModal('scrap')}><TrashIcon />{t('action_scrap')}</button>}
        </>
      }
    >
      <div className="row wrap">
        <StatusBadge status={v.status} />
        <Plate plate={v.plate} large />
        {v.reservedName && <span className="badge accent">{t('ui_reserved_for', v.reservedName)}</span>}
      </div>
      <div className="card card-pad stack s8">
        <div className="row between"><span className="faint">{t('ui_price')}</span><b style={{ fontSize: 18 }}>{money(v.price)}</b></div>
        {v.listPrice ? <div className="row between"><span className="faint">{t('ui_list')}</span><span>{money(v.listPrice)}</span></div> : null}
        <div className="row between"><span className="faint">{t('ui_cost')}</span><span>{money(v.cost)}</span></div>
        {v.cost > 0 && <div className="row between"><span className="faint">{t('ui_margin')}</span><span className={v.price - v.cost >= 0 ? '' : 'accent'}>{money(v.price - v.cost)}</span></div>}
      </div>
      <ConditionMeter condition={v.condition} />
      <div className="kv">
        <span>{t('ui_model')}</span><span className="mono">{v.model}</span>
        <span>{t('ui_type')}</span><span>{t(`vtype_${v.vtype}`)}</span>
        <span>{t('ui_source')}</span><span>{t(`source_${v.source}`)}</span>
        {v.displayLabel && <><span>{t('ui_display')}</span><span>{v.displayLabel}</span></>}
        {v.deliveryLabel && <><span>{t('ui_delivery_point')}</span><span>{v.deliveryLabel}</span></>}
        {v.storageFee > 0 && <><span>{t('ui_storage_fee')}</span><span className="accent">{money(v.storageFee)}</span></>}
        {v.orderedBy && <><span>{t('ui_ordered_by')}</span><span>{v.orderedBy}</span></>}
        {v.note && <><span>{t('stock_note')}</span><span>{v.note}</span></>}
        <span>{t('ui_since')}</span><span>{dateTime(v.createdAt)}</span>
        <span>{t('ui_engine')}</span><span>{Math.round((v.condition?.engine ?? 1000) / 10)} %</span>
        <span>{t('ui_body')}</span><span>{Math.round((v.condition?.body ?? 1000) / 10)} %</span>
        <span>{t('ui_fuel')}</span><span>{Math.round(v.condition?.fuel ?? 100)} %</span>
      </div>
      {v.status === 'waiting' && v.deliveryLabel && (
        <div className="notice"><MapPinIcon /><span>{t('ui_waiting_hint', v.deliveryLabel)}</span></div>
      )}
      {v.history.length > 0 && (
        <div className="stack s8">
          <div className="label">{t('ui_history')}</div>
          {v.history.map((h, i) => (
            <div key={i} className="log-item">
              <span className="log-dot" />
              <div>
                <div className="log-text">{t(`audit_${h.action.replace(/\./g, '_')}`)}</div>
                <div className="faint" style={{ fontSize: 11.5 }}>{h.actor_name || '-'} · {relative(h.created_at)}</div>
              </div>
            </div>
          ))}
        </div>
      )}
      {modal === 'price' && <PriceModal vehicle={v} onClose={() => setModal(null)} onDone={done} />}
      {modal === 'display' && <DisplayPickModal vehicle={v} onClose={() => setModal(null)} onDone={done} />}
      {modal === 'sell' && <SellModal vehicle={v} onClose={() => setModal(null)} onDone={() => { setModal(null); props.onChanged(); }} />}
      {modal === 'reserve' && <ReserveModal vehicle={v} onClose={() => setModal(null)} onDone={done} />}
      {modal === 'recall' && (
        <Confirm title={t('action_recall')} text={t('action_recall_desc')} onCancel={() => setModal(null)}
          onConfirm={async () => { if (await call('stock.recall', { stockId: v.id }, t('ui_saved'))) done(); }} />
      )}
      {(modal === 'release' || modal === 'scrap') && (
        <Confirm title={modal === 'scrap' ? t('action_scrap') : t('action_release')} text={modal === 'scrap' ? t('scrap_text') : t('action_release_desc')} danger
          onCancel={() => setModal(null)}
          onConfirm={async () => {
            if (await call('stock.remove', { stockId: v.id, mode: modal }, t('ui_saved'))) {
              props.onChanged();
              props.onClose();
            }
          }} />
      )}
    </Drawer>
  );
}

export function StockView(props: { initialFilter?: string; openId?: number }) {
  const { call } = useApp();
  const [filter, setFilter] = useState<Filter>((props.initialFilter as Filter) || 'all');
  const [query, setQuery] = useState('');
  const q = useDebounced(query, 250);
  const [list, setList] = useState<StockItem[] | null>(null);
  const [open, setOpen] = useState<number | null>(props.openId ?? null);

  const load = useCallback(async () => {
    const d = await call<StockItem[]>('stock.list', { statuses: FILTERS[filter], query: q });
    setList(d || []);
  }, [call, filter, q]);

  useEffect(() => {
    void load();
  }, [load]);

  const totals = useMemo(() => {
    const items = list || [];
    return { count: items.length, value: items.reduce((s, v) => s + (v.price || 0), 0) };
  }, [list]);

  return (
    <div className="stack">
      <div className="toolbar">
        <div className="input-wrap">
          <MagnifyingGlassIcon />
          <input className="input" placeholder={t('ui_search_stock')} value={query} onChange={(e) => setQuery(e.target.value)} />
        </div>
        <Segmented<Filter>
          value={filter}
          onChange={setFilter}
          options={[
            { value: 'all', label: t('ui_filter_all') },
            { value: 'storage', label: t('status_storage') },
            { value: 'display', label: t('status_display') },
            { value: 'out', label: t('ui_filter_out') },
          ]}
        />
        <span className="faint">{t('ui_stock_totals', totals.count, money(totals.value))}</span>
      </div>
      {!list ? <ListSkeleton rows={6} /> : list.length === 0 ? (
        <Empty title={t('ui_stock_empty')} text={t('ui_stock_empty_text')} />
      ) : (
        <div className="vgrid">
          {list.map((v) => (
            <div key={v.id} className="card vcard" onClick={() => setOpen(v.id)}>
              <div className="row">
                <TypeBadge type={v.vtype} />
                <div className="flex1" style={{ minWidth: 0 }}>
                  <div className="vtitle ellipsis">{v.label}</div>
                  <div className="faint ellipsis" style={{ fontSize: 12 }}>{v.brand || t(`vtype_${v.vtype}`)}</div>
                </div>
                <StatusBadge status={v.status} />
              </div>
              <div className="row between">
                <Plate plate={v.plate} />
                <span className="vprice">{money(v.price)}</span>
              </div>
              <ConditionMeter condition={v.condition} compact />
              {v.displayLabel && <span className="faint" style={{ fontSize: 12 }}>{t('ui_on_display', v.displayLabel)}</span>}
            </div>
          ))}
        </div>
      )}
      {open !== null && <VehicleDrawer id={open} onClose={() => setOpen(null)} onChanged={() => void load()} />}
    </div>
  );
}
