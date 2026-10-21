import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  BuildingStorefrontIcon,
  BookOpenIcon,
  MapPinIcon,
  ClockIcon,
  PlusIcon,
  TrashIcon,
  MapIcon,
  ArrowDownTrayIcon,
  MagnifyingGlassIcon,
  ComputerDesktopIcon,
  ArrowPathIcon,
  PencilSquareIcon,
} from '@heroicons/react/24/outline';
import { myPosition, rpc, waypoint } from '../lib/rpc';
import { setStrings, t } from '../lib/i18n';
import { dateTime, money, setCurrency } from '../lib/format';
import type { CatalogEntry, Meta, ShopSettings, ShopType, Vec4, VehicleType } from '../lib/types';
import { Confirm, Empty, Field, Loading, Modal, NumberInput, Segmented, Toggle, useDebounced, useToast } from '../components/ui';
import { TypeBadge } from '../components/vs';

interface AdminDisplay {
  id: number; label: string; x: number; y: number; z: number; h: number; types: VehicleType[];
  sign: { enabled: boolean; offset: { x: number; y: number; z: number; h: number }; world?: Vec4 | null };
  kind: 'stock' | 'showcase'; turntable: boolean; sort: number; showcaseModel?: string | null; showcaseColor?: number | null;
  vehicle?: { label: string; plate?: string; status: string } | null;
}

interface AdminShop {
  id: number; label: string; type: ShopType; job?: string | null; ownerId?: string | null; ownerName?: string | null;
  active: boolean; npcActive: boolean; staffOnDuty: number; settings: ShopSettings;
  points: Partial<Record<'manage' | 'npc' | 'handover' | 'dropoff', Vec4>>;
  policy: Record<string, number>;
  catalog: { mode: 'all' | 'whitelist' | 'blacklist'; models: string[]; categories: string[]; types: VehicleType[] };
  balance: number; counts: Record<string, number>; displays: AdminDisplay[];
}

interface OverviewShop { id: number; label: string; type: ShopType; job?: string | null; active: boolean; npcActive: boolean; balance: number; displays: number; counts: Record<string, number>; ownerName?: string | null }

interface DeliveryPoint {
  id: string; label: string; types: VehicleType[]; interact?: Vec4 | null; npc?: string | null; enabled: boolean;
  spawns: Vec4[]; waterSpawns: Vec4[]; airSpawns: Vec4[];
}

interface AdminSession { strings: Record<string, string>; meta: Meta; currency: string }

type Tab = 'shops' | 'catalog' | 'points' | 'audit';

function useCall() {
  const toast = useToast();
  return useCallback(async <T,>(action: string, payload: Record<string, unknown> = {}, okText?: string): Promise<T | null> => {
    const res = await rpc<T>(action, payload);
    if (!res.ok) {
      toast('error', res.message || String(res.error));
      return null;
    }
    if (okText) toast('ok', okText);
    return (res.data ?? (true as unknown)) as T;
  }, [toast]);
}

function coordText(p?: Vec4 | null) {
  if (!p) return t('admin_point_missing');
  return `${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}`;
}

function TypeChips(props: { value: VehicleType[]; onChange: (v: VehicleType[]) => void; types: VehicleType[] }) {
  return (
    <div className="chips">
      {props.types.map((ty) => {
        const on = props.value.includes(ty);
        return (
          <button key={ty} className={`chip ${on ? 'on' : ''}`} onClick={() => props.onChange(on ? props.value.filter((x) => x !== ty) : [...props.value, ty])}>
            {t(`vtype_${ty}`)}
          </button>
        );
      })}
    </div>
  );
}

/** "At my position" needs the player in the world; the admin panel runs on the computer in the game. */
function PositionButton(props: { onPosition: (p: Vec4) => void; label?: string; small?: boolean }) {
  const toast = useToast();
  return (
    <button className={`btn ${props.small ? 'sm' : ''}`} onClick={async () => {
      const p = await myPosition();
      if (!p) {
        toast('error', t('admin_no_position'));
        return;
      }
      props.onPosition({ x: p.x, y: p.y, z: p.z, w: p.w });
    }}>
      <MapPinIcon />{props.label || t('admin_point_here')}
    </button>
  );
}

// Shop editor -------------------------------------------------------------------------------

type ShopTab = 'general' | 'points' | 'displays' | 'settings' | 'catalog' | 'policy';

function GeneralTab({ shop, meta, onSaved }: { shop: AdminShop; meta: Meta; onSaved: (s: AdminShop) => void }) {
  const call = useCall();
  const [label, setLabel] = useState(shop.label);
  const [type, setType] = useState<ShopType>(shop.type);
  const [job, setJob] = useState(shop.job || '');
  const [ownerId, setOwnerId] = useState(shop.ownerId || '');
  const [active, setActive] = useState(shop.active);
  const [query, setQuery] = useState('');
  const q = useDebounced(query, 250);
  const [players, setPlayers] = useState<Array<{ identifier: string; name: string; job: string }>>([]);
  const [balance, setBalance] = useState<number | undefined>();
  useEffect(() => {
    if (!q) {
      setPlayers([]);
      return;
    }
    void call<Array<{ identifier: string; name: string; job: string }>>('admin.players', { query: q }).then((d) => setPlayers(d || []));
  }, [q, call]);
  void meta;
  return (
    <div className="stack s20">
      <div className="card card-body grid c2">
        <Field label={t('admin_shop_label')}><input className="input" value={label} onChange={(e) => setLabel(e.target.value)} maxLength={64} /></Field>
        <Field label={t('admin_shop_type')} hint={t(`admin_type_hint_${type}`)}>
          <Segmented<ShopType> value={type} onChange={setType} options={[
            { value: 'npc', label: t('shoptype_npc') },
            { value: 'player', label: t('shoptype_player') },
            { value: 'mixed', label: t('shoptype_mixed') },
          ]} />
        </Field>
        <Field label={t('admin_shop_job')} hint={t('admin_shop_job_desc')}><input className="input" value={job} disabled={type === 'npc'} onChange={(e) => setJob(e.target.value)} /></Field>
        <Field label={t('admin_shop_active')}><Toggle checked={active} onChange={setActive} label={active ? t('ui_yes') : t('admin_inactive')} /></Field>
        <Field label={t('admin_shop_owner')} hint={t('admin_shop_owner_desc')} className="span-all">
          <div className="stack s8">
            <input className="input mono" value={ownerId} onChange={(e) => setOwnerId(e.target.value)} placeholder={t('admin_owner_placeholder')} disabled={type === 'npc'} />
            {shop.ownerName && <span className="faint">{t('admin_current_owner', shop.ownerName)}</span>}
            {type !== 'npc' && (
              <div className="input-wrap"><MagnifyingGlassIcon /><input className="input" value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t('admin_search_player')} /></div>
            )}
            {players.length > 0 && (
              <div className="chips">
                {players.map((p) => <button key={p.identifier} className={`chip ${ownerId === p.identifier ? 'on' : ''}`} onClick={() => setOwnerId(p.identifier)}>{p.name} <span className="faint">{p.job}</span></button>)}
              </div>
            )}
          </div>
        </Field>
      </div>
      <div className="row">
        <div className="flex1" />
        <button className="btn primary" onClick={async () => {
          const s = await call<AdminShop>('admin.shop.update', { shopId: shop.id, shop: { label, type, job, ownerId, active } }, t('ui_saved'));
          if (s) onSaved(s);
        }}>{t('ui_save')}</button>
      </div>
      <div className="card">
        <div className="card-head"><div className="h2">{t('admin_balance')}</div><b>{money(shop.balance)}</b></div>
        <div className="card-body row">
          <div className="flex1"><NumberInput value={balance} onChange={setBalance} placeholder={t('admin_balance_desc')} /></div>
          <button className="btn" disabled={!balance} onClick={async () => {
            const s = await call<AdminShop>('admin.shop.balance', { shopId: shop.id, amount: balance }, t('ui_saved'));
            if (s) { setBalance(undefined); onSaved(s); }
          }}>{t('admin_book')}</button>
          <button className="btn" disabled={!balance} onClick={async () => {
            const s = await call<AdminShop>('admin.shop.balance', { shopId: shop.id, amount: -(balance || 0) }, t('ui_saved'));
            if (s) { setBalance(undefined); onSaved(s); }
          }}>{t('admin_book_minus')}</button>
        </div>
      </div>
    </div>
  );
}

function PointsTab({ shop, onSaved }: { shop: AdminShop; onSaved: (s: AdminShop) => void }) {
  const call = useCall();
  const keys: Array<'manage' | 'npc' | 'handover' | 'dropoff'> = ['manage', 'npc', 'handover', 'dropoff'];
  return (
    <div className="stack">
      <div className="notice neutral"><ComputerDesktopIcon /><span>{t('admin_points_intro')}</span></div>
      <div className="card">
        {keys.map((key) => {
          const p = shop.points[key];
          return (
            <div key={key} className="list-item" style={{ cursor: 'default' }}>
              <div className="flex1">
                <div className="h3">{t(`point_key_${key}`)}</div>
                <div className="faint" style={{ fontSize: 12 }}>{t(`point_key_${key}_desc`)}</div>
                <div className="coord">{coordText(p)}</div>
              </div>
              {p && <button className="icon-btn" title={t('admin_point_goto')} onClick={() => waypoint(p.x, p.y)}><MapIcon /></button>}
              <PositionButton small onPosition={async (pos) => {
                const s = await call<AdminShop>('admin.shop.point', { shopId: shop.id, key, coords: pos }, t('ui_saved'));
                if (s) onSaved(s);
              }} />
              {p && <button className="icon-btn danger" onClick={async () => {
                const s = await call<AdminShop>('admin.shop.point', { shopId: shop.id, key, coords: false }, t('ui_saved'));
                if (s) onSaved(s);
              }}><TrashIcon /></button>}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function DisplayEditor(props: { shop: AdminShop; display: AdminDisplay; meta: Meta; onSaved: (s: AdminShop) => void; onClose: () => void }) {
  const call = useCall();
  const d = props.display;
  const [label, setLabel] = useState(d.label);
  const [kind, setKind] = useState(d.kind);
  const [types, setTypes] = useState<VehicleType[]>(d.types);
  const [turntable, setTurntable] = useState(d.turntable);
  const [sign, setSign] = useState(d.sign.enabled);
  const [offset, setOffset] = useState(d.sign.offset);
  const save = async (extra: Record<string, unknown> = {}) => {
    const s = await call<AdminShop>('admin.display.update', {
      displayId: d.id,
      display: { label, kind, types, turntable, sign: { enabled: sign, offset }, ...extra },
    }, t('ui_saved'));
    if (s) props.onSaved(s);
    return s;
  };
  return (
    <Modal title={label || t('display_number', d.id)} onClose={props.onClose} size="wide"
      footer={<>
        <button className="btn ghost" onClick={props.onClose}>{t('ui_close')}</button>
        <button className="btn primary" onClick={async () => { if (await save()) props.onClose(); }}>{t('ui_save')}</button>
      </>}>
      <div className="stack">
        <div className="grid c2">
          <Field label={t('admin_display_label')}><input className="input" value={label} onChange={(e) => setLabel(e.target.value)} maxLength={64} /></Field>
          <Field label={t('admin_display_kind')} hint={t('admin_display_kind_desc')}>
            <Segmented value={kind} onChange={setKind} options={[{ value: 'stock', label: t('display_kind_stock') }, { value: 'showcase', label: t('display_kind_showcase') }]} />
          </Field>
        </div>
        <Field label={t('admin_display_types')} hint={t('admin_display_types_hint')}>
          <TypeChips value={types} onChange={setTypes} types={props.meta.types} />
        </Field>
        <div className="grid c2">
          <Field label={t('admin_display_turntable')}><Toggle checked={turntable} onChange={setTurntable} /></Field>
          <Field label={t('admin_display_position')} hint={coordText({ x: d.x, y: d.y, z: d.z, w: d.h })}>
            <div className="row wrap">
              <PositionButton small label={t('admin_display_move')} onPosition={(pos) => void save({ coords: pos })} />
              <button className="btn sm" onClick={() => waypoint(d.x, d.y)}><MapIcon />{t('admin_point_goto')}</button>
            </div>
          </Field>
        </div>
        <div className="card">
          <div className="card-head"><div className="h2">{t('admin_sign')}</div><Toggle checked={sign} onChange={setSign} /></div>
          <div className="card-body stack">
            <span className="faint" style={{ fontSize: 12 }}>{t('admin_sign_intro')}</span>
            <div className="grid c4">
              {(['x', 'y', 'z', 'h'] as const).map((k) => (
                <Field key={k} label={t(`admin_offset_${k}`)}>
                  <NumberInput value={offset[k]} onChange={(v) => setOffset((o) => ({ ...o, [k]: v ?? 0 }))} disabled={!sign} />
                </Field>
              ))}
            </div>
            <div className="row wrap">
              <PositionButton small label={t('admin_sign_here')} onPosition={(pos) => void save({ sign: { enabled: true, world: { ...pos, w: ((pos.w || 0) + 180) % 360 } } })} />
              <button className="btn sm" onClick={() => void save({ sign: { enabled: sign, world: false, offset } })}>{t('admin_sign_reset')}</button>
              {d.sign.world && <span className="faint">{t('admin_sign_world', coordText(d.sign.world))}</span>}
            </div>
          </div>
        </div>
      </div>
    </Modal>
  );
}

function DisplaysTab({ shop, meta, onSaved }: { shop: AdminShop; meta: Meta; onSaved: (s: AdminShop) => void }) {
  const call = useCall();
  const [edit, setEdit] = useState<AdminDisplay | null>(null);
  const [del, setDel] = useState<AdminDisplay | null>(null);
  const [newTypes, setNewTypes] = useState<VehicleType[]>(['car', 'offroad', 'van']);
  const [newKind, setNewKind] = useState<'stock' | 'showcase'>(shop.type === 'npc' ? 'showcase' : 'stock');
  return (
    <div className="stack">
      <div className="card">
        <div className="card-head"><PlusIcon style={{ width: 18 }} /><div className="h2">{t('admin_display_add')}</div></div>
        <div className="card-body stack">
          <span className="faint" style={{ fontSize: 12 }}>{t('admin_display_add_desc')}</span>
          <TypeChips value={newTypes} onChange={setNewTypes} types={meta.types} />
          <div className="row wrap">
            <Segmented value={newKind} onChange={setNewKind} options={[{ value: 'stock', label: t('display_kind_stock') }, { value: 'showcase', label: t('display_kind_showcase') }]} />
            <div className="flex1" />
            <PositionButton label={t('admin_display_add_here')} onPosition={async (pos) => {
              const s = await call<AdminShop>('admin.display.create', { shopId: shop.id, display: { coords: pos, types: newTypes, kind: newKind } }, t('admin_display_added'));
              if (s) onSaved(s);
            }} />
          </div>
        </div>
      </div>
      {shop.displays.length === 0 ? <Empty title={t('ui_no_spots')} text={t('admin_no_spots_text')} /> : (
        <div className="spots">
          {shop.displays.map((d) => (
            <div key={d.id} className={`spot ${d.vehicle ? 'taken' : ''}`}>
              <div className="row between"><b className="ellipsis">{d.label || t('display_number', d.id)}</b><span className="pill">{t(`display_kind_${d.kind}`)}</span></div>
              <div className="types">{d.types.map((ty) => <span key={ty} className="pill">{t(`vtype_${ty}`)}</span>)}</div>
              <span className="coord">{coordText({ x: d.x, y: d.y, z: d.z })}</span>
              {d.vehicle && <span className="faint" style={{ fontSize: 12 }}>{d.vehicle.label} · {d.vehicle.plate}</span>}
              {d.kind === 'showcase' && d.showcaseModel && <span className="faint" style={{ fontSize: 12 }}>{d.showcaseModel}</span>}
              <div className="row">
                <button className="btn sm flex1" onClick={() => setEdit(d)}><PencilSquareIcon />{t('admin_display_edit')}</button>
                <button className="icon-btn" onClick={() => waypoint(d.x, d.y)}><MapIcon /></button>
                <button className="icon-btn danger" disabled={!!d.vehicle} onClick={() => setDel(d)}><TrashIcon /></button>
              </div>
            </div>
          ))}
        </div>
      )}
      {edit && <DisplayEditor shop={shop} display={edit} meta={meta} onSaved={onSaved} onClose={() => setEdit(null)} />}
      {del && (
        <Confirm title={t('admin_display_delete')} text={t('admin_display_delete_text')} danger onCancel={() => setDel(null)}
          onConfirm={async () => {
            const s = await call<AdminShop>('admin.display.delete', { displayId: del.id }, t('ui_saved'));
            if (s) onSaved(s);
            setDel(null);
          }} />
      )}
    </div>
  );
}

function SettingsTab({ shop, meta, onSaved }: { shop: AdminShop; meta: Meta; onSaved: (s: AdminShop) => void }) {
  const call = useCall();
  const [s, setS] = useState<ShopSettings>(JSON.parse(JSON.stringify(shop.settings)));
  const n = (key: keyof ShopSettings, label: string, hint?: string) => (
    <Field label={label} hint={hint}><NumberInput value={s[key] as number} onChange={(v) => setS((x) => ({ ...x, [key]: v ?? 0 }))} /></Field>
  );
  return (
    <div className="stack s20">
      <div className="card">
        <div className="card-head"><div className="h2">{t('admin_prices')}</div></div>
        <div className="card-body grid c3">
          {n('wholesaleMultiplier', t('set_wholesaleMultiplier'), t('admin_hint_wholesale'))}
          {n('npcPriceMultiplier', t('set_npcPriceMultiplier'), t('admin_hint_npc_price'))}
          {n('mixedNpcMultiplier', t('set_mixedNpcMultiplier'), t('admin_hint_mixed_price'))}
          {n('commissionPercent', t('set_commissionPercent'))}
          {n('maxDiscountPercent', t('set_maxDiscountPercent'))}
          <Field label={t('ui_currency')}><input className="input" value={s.currency} maxLength={4} onChange={(e) => setS((x) => ({ ...x, currency: e.target.value }))} /></Field>
        </div>
      </div>
      <div className="card">
        <div className="card-head"><div className="h2">{t('admin_operation')}</div></div>
        <div className="card-body grid c3">
          {n('minStaffOnline', t('set_minStaffOnline'), t('admin_hint_min_staff'))}
          {n('storageLimit', t('set_storageLimit'), t('admin_hint_storage'))}
          {n('dropoffRadius', t('set_dropoffRadius'))}
          <Field label={t('set_npcModel')}><input className="input mono" value={s.npcModel} onChange={(e) => setS((x) => ({ ...x, npcModel: e.target.value }))} /></Field>
          <Field label={t('set_npcDelivery')} hint={t('admin_hint_npc_delivery')}><Toggle checked={s.npcDelivery} onChange={(v) => setS((x) => ({ ...x, npcDelivery: v }))} /></Field>
        </div>
      </div>
      <div className="card">
        <div className="card-head"><div className="h2">{t('set_blip')}</div><Toggle checked={s.blip.enabled} onChange={(v) => setS((x) => ({ ...x, blip: { ...x.blip, enabled: v } }))} /></div>
        <div className="card-body grid c3">
          <Field label={t('set_blipSprite')}><NumberInput value={s.blip.sprite} onChange={(v) => setS((x) => ({ ...x, blip: { ...x.blip, sprite: v ?? 326 } }))} /></Field>
          <Field label={t('set_blipColor')}><NumberInput value={s.blip.color} onChange={(v) => setS((x) => ({ ...x, blip: { ...x.blip, color: v ?? 3 } }))} /></Field>
          <Field label={t('admin_blip_scale')}><NumberInput value={s.blip.scale} onChange={(v) => setS((x) => ({ ...x, blip: { ...x.blip, scale: v ?? 0.8 } }))} /></Field>
        </div>
      </div>
      <div className="card">
        <div className="card-head"><div className="h2">{t('admin_customer_features')}</div></div>
        <div className="card-body grid c3">
          <Field label={t('set_testDrive')}><Toggle checked={s.testDrive.enabled} onChange={(v) => setS((x) => ({ ...x, testDrive: { ...x.testDrive, enabled: v } }))} /></Field>
          <Field label={t('set_testDriveSeconds')}><NumberInput value={s.testDrive.seconds} onChange={(v) => setS((x) => ({ ...x, testDrive: { ...x.testDrive, seconds: v ?? 180 } }))} /></Field>
          <Field label={t('set_testDriveDeposit')}><NumberInput value={s.testDrive.deposit} onChange={(v) => setS((x) => ({ ...x, testDrive: { ...x.testDrive, deposit: v ?? 0 } }))} /></Field>
          <Field label={t('set_finance')}><Toggle checked={s.finance.enabled} onChange={(v) => setS((x) => ({ ...x, finance: { ...x.finance, enabled: v } }))} /></Field>
          <Field label={t('ui_down_payment_percent')}><NumberInput value={s.finance.downPaymentPercent} onChange={(v) => setS((x) => ({ ...x, finance: { ...x.finance, downPaymentPercent: v ?? 0 } }))} /></Field>
          <Field label={t('ui_installments')}><NumberInput value={s.finance.installments} onChange={(v) => setS((x) => ({ ...x, finance: { ...x.finance, installments: v ?? 2 } }))} /></Field>
          <Field label={t('ui_interval_minutes')}><NumberInput value={s.finance.intervalMinutes} onChange={(v) => setS((x) => ({ ...x, finance: { ...x.finance, intervalMinutes: v ?? 60 } }))} /></Field>
          <Field label={t('ui_interest_percent')}><NumberInput value={s.finance.interestPercent} onChange={(v) => setS((x) => ({ ...x, finance: { ...x.finance, interestPercent: v ?? 0 } }))} /></Field>
          <Field label={t('set_tradeIn')}><Toggle checked={s.tradeIn.enabled} onChange={(v) => setS((x) => ({ ...x, tradeIn: { ...x.tradeIn, enabled: v } }))} /></Field>
          <Field label={t('set_tradeInNpcPercent')}><NumberInput value={s.tradeIn.npcPercent} onChange={(v) => setS((x) => ({ ...x, tradeIn: { ...x.tradeIn, npcPercent: v ?? 0 } }))} /></Field>
        </div>
      </div>
      <div className="card">
        <div className="card-head"><div className="h2">{t('ui_delivery_points')}</div></div>
        <div className="card-body chips">
          {meta.points.map((p) => {
            const on = s.deliveryPoints.length === 0 || s.deliveryPoints.includes(p.id);
            return (
              <button key={p.id} className={`chip ${on ? 'on' : ''}`} onClick={() => {
                const all = meta.points.map((x) => x.id);
                const current = s.deliveryPoints.length === 0 ? all : s.deliveryPoints;
                const next = on ? current.filter((x) => x !== p.id) : [...current, p.id];
                setS((x) => ({ ...x, deliveryPoints: next.length === all.length ? [] : next }));
              }}>{p.label}</button>
            );
          })}
        </div>
      </div>
      <div className="row"><div className="flex1" /><button className="btn primary" onClick={async () => {
        const r = await call<AdminShop>('admin.shop.update', { shopId: shop.id, shop: { settings: s } }, t('ui_saved'));
        if (r) onSaved(r);
      }}>{t('ui_save')}</button></div>
    </div>
  );
}

function CatalogFilterTab({ shop, meta, onSaved }: { shop: AdminShop; meta: Meta; onSaved: (s: AdminShop) => void }) {
  const call = useCall();
  const [f, setF] = useState(JSON.parse(JSON.stringify(shop.catalog)) as AdminShop['catalog']);
  const [catalog, setCatalog] = useState<CatalogEntry[]>([]);
  const [query, setQuery] = useState('');
  useEffect(() => {
    void call<CatalogEntry[]>('admin.catalog.list').then((d) => setCatalog(d || []));
  }, [call]);
  const matches = catalog.filter((e) => query && (e.label.toLowerCase().includes(query.toLowerCase()) || e.model.includes(query.toLowerCase()))).slice(0, 12);
  return (
    <div className="stack s20">
      <div className="card card-body stack">
        <Field label={t('admin_catalog_mode')} hint={t(`admin_catalog_mode_hint_${f.mode}`)}>
          <Segmented value={f.mode} onChange={(mode) => setF((x) => ({ ...x, mode }))} options={[
            { value: 'all', label: t('catalog_mode_all') },
            { value: 'whitelist', label: t('catalog_mode_whitelist') },
            { value: 'blacklist', label: t('catalog_mode_blacklist') },
          ]} />
        </Field>
        <Field label={t('admin_catalog_types')} hint={t('admin_catalog_types_desc')}>
          <TypeChips value={f.types} onChange={(types) => setF((x) => ({ ...x, types }))} types={meta.types} />
        </Field>
        <Field label={t('admin_catalog_categories')} hint={t('admin_catalog_categories_hint')}>
          <div className="chips">
            {meta.categories.map((c) => {
              const on = f.categories.includes(c);
              return <button key={c} className={`chip ${on ? 'on' : ''}`} disabled={f.mode === 'all'} onClick={() => setF((x) => ({ ...x, categories: on ? x.categories.filter((y) => y !== c) : [...x.categories, c] }))}>{t(`category_${c}`)}</button>;
            })}
          </div>
        </Field>
        <Field label={t('admin_catalog_models')} hint={t('admin_catalog_models_hint')}>
          <div className="stack s8">
            <div className="chips">
              {f.models.map((m) => <button key={m} className="chip on" onClick={() => setF((x) => ({ ...x, models: x.models.filter((y) => y !== m) }))}>{m} ×</button>)}
              {f.models.length === 0 && <span className="faint">{t('admin_no_models')}</span>}
            </div>
            <div className="input-wrap"><MagnifyingGlassIcon /><input className="input" disabled={f.mode === 'all'} value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t('ui_search_catalog')} /></div>
            {matches.length > 0 && (
              <div className="chips">
                {matches.map((e) => <button key={e.model} className="chip" onClick={() => { setF((x) => ({ ...x, models: x.models.includes(e.model) ? x.models : [...x.models, e.model] })); setQuery(''); }}>{e.label} <span className="faint">{e.model}</span></button>)}
              </div>
            )}
          </div>
        </Field>
      </div>
      <div className="row"><div className="flex1" /><button className="btn primary" onClick={async () => {
        const r = await call<AdminShop>('admin.shop.update', { shopId: shop.id, shop: { catalog: f } }, t('ui_saved'));
        if (r) onSaved(r);
      }}>{t('ui_save')}</button></div>
    </div>
  );
}

function PolicyTab({ shop, meta, onSaved }: { shop: AdminShop; meta: Meta; onSaved: (s: AdminShop) => void }) {
  const call = useCall();
  const [p, setP] = useState<Record<string, number>>({ ...shop.policy });
  return (
    <div className="card card-body stack s8">
      <span className="faint" style={{ fontSize: 12 }}>{t('admin_policy_intro')}</span>
      {meta.policyKeys.map((key) => (
        <div key={key} className="row between">
          <span>{t(`policy_${key}`)}</span>
          <NumberInput value={p[key]} onChange={(v) => setP((x) => ({ ...x, [key]: v ?? 0 }))} style={{ width: 90 }} />
        </div>
      ))}
      <div className="row"><div className="flex1" /><button className="btn primary" onClick={async () => {
        const r = await call<AdminShop>('admin.shop.update', { shopId: shop.id, shop: { policy: p } }, t('ui_saved'));
        if (r) onSaved(r);
      }}>{t('ui_save')}</button></div>
    </div>
  );
}

function ShopEditor({ shopId, meta, onChanged, onDeleted }: { shopId: number; meta: Meta; onChanged: () => void; onDeleted: () => void }) {
  const call = useCall();
  const [shop, setShop] = useState<AdminShop | null>(null);
  const [tab, setTab] = useState<ShopTab>('general');
  const [del, setDel] = useState(false);
  const load = useCallback(async () => {
    const s = await call<AdminShop>('admin.shop.get', { shopId });
    if (s) setShop(s);
  }, [call, shopId]);
  useEffect(() => {
    setShop(null);
    void load();
  }, [load]);
  const saved = (s: AdminShop) => {
    setShop(s);
    onChanged();
  };
  if (!shop) return <Loading />;
  return (
    <div className="stack">
      <div className="row">
        <div className="flex1">
          <div className="h2">{shop.label}</div>
          <div className="faint" style={{ fontSize: 12 }}>{t(`shoptype_${shop.type}`)} · {shop.job || '-'} · {shop.ownerName || t('admin_no_owner')}</div>
        </div>
        <span className={`badge ${shop.npcActive ? 'warn' : 'ok'}`}>{shop.npcActive ? t('ui_npc_active') : t('ui_staff_active')}</span>
        <button className="btn sm danger" onClick={() => setDel(true)}><TrashIcon />{t('admin_delete_shop')}</button>
      </div>
      <div className="tabs" style={{ marginTop: 0 }}>
        {(['general', 'points', 'displays', 'settings', 'catalog', 'policy'] as ShopTab[]).map((k) => (
          <button key={k} className={`tab ${tab === k ? 'on' : ''}`} onClick={() => setTab(k)}>
            {t(`admin_tab_${k}`)}{k === 'displays' && <span className="count">{shop.displays.length}</span>}
          </button>
        ))}
      </div>
      {tab === 'general' && <GeneralTab key={shop.id} shop={shop} meta={meta} onSaved={saved} />}
      {tab === 'points' && <PointsTab shop={shop} onSaved={saved} />}
      {tab === 'displays' && <DisplaysTab shop={shop} meta={meta} onSaved={saved} />}
      {tab === 'settings' && <SettingsTab key={shop.id} shop={shop} meta={meta} onSaved={saved} />}
      {tab === 'catalog' && <CatalogFilterTab key={shop.id} shop={shop} meta={meta} onSaved={saved} />}
      {tab === 'policy' && <PolicyTab key={shop.id} shop={shop} meta={meta} onSaved={saved} />}
      {del && (
        <Confirm title={t('admin_delete_shop')} text={t('admin_delete_shop_desc')} danger onCancel={() => setDel(false)}
          onConfirm={async () => {
            const r = await call<{ deleted?: boolean }>('admin.shop.delete', { shopId: shop.id }, t('ui_saved'));
            setDel(false);
            if (r) onDeleted();
          }} />
      )}
    </div>
  );
}

function NewShopModal(props: { onClose: () => void; onCreated: (id: number) => void }) {
  const call = useCall();
  const [label, setLabel] = useState('');
  const [type, setType] = useState<ShopType>('player');
  const [job, setJob] = useState('cardealer');
  return (
    <Modal title={t('admin_new_shop')} onClose={props.onClose}
      footer={<>
        <button className="btn ghost" onClick={props.onClose}>{t('ui_cancel')}</button>
        <button className="btn primary" disabled={!label || (type !== 'npc' && !job)} onClick={async () => {
          const s = await call<AdminShop>('admin.shop.create', { shop: { label, type, job } }, t('admin_shop_created'));
          if (s) props.onCreated(s.id);
        }}>{t('ui_create')}</button>
      </>}>
      <div className="stack">
        <Field label={t('admin_shop_label')}><input className="input" value={label} autoFocus onChange={(e) => setLabel(e.target.value)} /></Field>
        <Field label={t('admin_shop_type')} hint={t(`admin_type_hint_${type}`)}>
          <Segmented<ShopType> value={type} onChange={setType} options={[
            { value: 'npc', label: t('shoptype_npc') },
            { value: 'player', label: t('shoptype_player') },
            { value: 'mixed', label: t('shoptype_mixed') },
          ]} />
        </Field>
        {type !== 'npc' && <Field label={t('admin_shop_job')} hint={t('admin_shop_job_desc')}><input className="input" value={job} onChange={(e) => setJob(e.target.value)} /></Field>}
        <div className="notice neutral">{t('admin_new_shop_next')}</div>
      </div>
    </Modal>
  );
}

function ShopsTab({ meta }: { meta: Meta }) {
  const call = useCall();
  const [list, setList] = useState<OverviewShop[] | null>(null);
  const [selected, setSelected] = useState<number | null>(null);
  const [creating, setCreating] = useState(false);
  const load = useCallback(async () => {
    const d = await call<OverviewShop[]>('admin.overview');
    if (d) {
      setList(d);
      setSelected((s) => (s && d.some((x) => x.id === s) ? s : d[0]?.id ?? null));
    }
  }, [call]);
  useEffect(() => {
    void load();
  }, [load]);
  if (!list) return <Loading />;
  return (
    <div className="split" style={{ height: '100%' }}>
      <div className="pane left">
        <div style={{ padding: 12 }}><button className="btn primary block" onClick={() => setCreating(true)}><PlusIcon />{t('admin_new_shop')}</button></div>
        {list.length === 0 ? <Empty title={t('admin_no_shops')} text={t('admin_no_shops_text')} /> : list.map((s) => (
          <div key={s.id} className={`list-item ${selected === s.id ? 'active' : ''}`} onClick={() => setSelected(s.id)}>
            <BuildingStorefrontIcon style={{ width: 18, height: 18, opacity: s.active ? 1 : 0.4 }} />
            <div className="flex1" style={{ minWidth: 0 }}>
              <div className="h3 ellipsis">{s.label}</div>
              <div className="faint" style={{ fontSize: 12 }}>{t(`shoptype_${s.type}`)} · {s.job || '-'} · {t('admin_spots_count', s.displays)}</div>
            </div>
            {!s.active && <span className="badge danger plain">{t('admin_inactive')}</span>}
          </div>
        ))}
      </div>
      <div className="pane" style={{ padding: '20px 24px 40px' }}>
        {selected ? <ShopEditor shopId={selected} meta={meta} onChanged={() => void load()} onDeleted={() => { setSelected(null); void load(); }} /> : <Empty title={t('admin_pick_shop')} />}
      </div>
      {creating && <NewShopModal onClose={() => setCreating(false)} onCreated={(id) => { setCreating(false); setSelected(id); void load(); }} />}
    </div>
  );
}

// Catalog -----------------------------------------------------------------------------------

function EntryModal(props: { entry: CatalogEntry | null; meta: Meta; onClose: () => void; onSaved: () => void }) {
  const call = useCall();
  const [e, setE] = useState<CatalogEntry>(props.entry || { model: '', label: '', brand: '', category: 'other', vtype: 'car', price: 10000, minutes: null, enabled: true });
  return (
    <Modal title={props.entry ? props.entry.label : t('admin_catalog_add')} onClose={props.onClose}
      footer={<>
        <button className="btn ghost" onClick={props.onClose}>{t('ui_cancel')}</button>
        <button className="btn primary" disabled={!e.model} onClick={async () => {
          if (await call('admin.catalog.save', { entry: e }, t('ui_saved'))) props.onSaved();
        }}>{t('ui_save')}</button>
      </>}>
      <div className="grid c2">
        <Field label={t('catalog_model')} hint={t('admin_model_hint')}><input className="input mono" value={e.model} disabled={!!props.entry} onChange={(x) => setE({ ...e, model: x.target.value.toLowerCase() })} /></Field>
        <Field label={t('catalog_label')}><input className="input" value={e.label} onChange={(x) => setE({ ...e, label: x.target.value })} /></Field>
        <Field label={t('catalog_brand')}><input className="input" value={e.brand} onChange={(x) => setE({ ...e, brand: x.target.value })} /></Field>
        <Field label={t('catalog_category')}>
          <select className="select" value={e.category} onChange={(x) => setE({ ...e, category: x.target.value })}>
            {props.meta.categories.map((c) => <option key={c} value={c}>{t(`category_${c}`)}</option>)}
          </select>
        </Field>
        <Field label={t('catalog_type')}>
          <select className="select" value={e.vtype} onChange={(x) => setE({ ...e, vtype: x.target.value as VehicleType })}>
            {props.meta.types.map((ty) => <option key={ty} value={ty}>{t(`vtype_${ty}`)}</option>)}
          </select>
        </Field>
        <Field label={t('catalog_price')}><NumberInput value={e.price} onChange={(v) => setE({ ...e, price: v ?? 0 })} /></Field>
        <Field label={t('catalog_minutes')} hint={t('catalog_minutes_desc')}><NumberInput value={e.minutes ?? undefined} onChange={(v) => setE({ ...e, minutes: v ?? null })} /></Field>
        <Field label={t('catalog_enabled')}><Toggle checked={e.enabled !== false} onChange={(v) => setE({ ...e, enabled: v })} /></Field>
      </div>
    </Modal>
  );
}

function CatalogTab({ meta }: { meta: Meta }) {
  const call = useCall();
  const [list, setList] = useState<CatalogEntry[] | null>(null);
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState('');
  const [edit, setEdit] = useState<CatalogEntry | null | 'new'>(null);
  const [del, setDel] = useState<CatalogEntry | null>(null);
  const load = useCallback(async () => {
    const d = await call<CatalogEntry[]>('admin.catalog.list');
    setList(d || []);
  }, [call]);
  useEffect(() => {
    void load();
  }, [load]);
  const shown = useMemo(() => (list || []).filter((e) =>
    (!query || e.label.toLowerCase().includes(query.toLowerCase()) || e.model.includes(query.toLowerCase())) && (!category || e.category === category)), [list, query, category]);
  if (!list) return <Loading />;
  return (
    <div className="stack" style={{ padding: '20px 24px 40px' }}>
      <div className="toolbar">
        <div className="input-wrap"><MagnifyingGlassIcon /><input className="input" value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t('ui_search_catalog')} /></div>
        <select className="select" style={{ width: 180 }} value={category} onChange={(e) => setCategory(e.target.value)}>
          <option value="">{t('ui_all_categories')}</option>
          {meta.categories.map((c) => <option key={c} value={c}>{t(`category_${c}`)}</option>)}
        </select>
        <div className="flex1" />
        <button className="btn" onClick={async () => {
          const r = await call<{ added: number }>('admin.catalog.import');
          if (r) { void load(); }
        }}><ArrowDownTrayIcon />{t('admin_catalog_import')}</button>
        <button className="btn primary" onClick={() => setEdit('new')}><PlusIcon />{t('admin_catalog_add')}</button>
      </div>
      <div className="notice neutral">{t('admin_catalog_intro')}</div>
      <div className="card">
        <table className="table">
          <thead><tr><th /><th>{t('catalog_label')}</th><th>{t('catalog_model')}</th><th className="hide-mobile">{t('catalog_category')}</th><th className="num">{t('catalog_price')}</th><th className="num hide-mobile">{t('catalog_minutes')}</th><th>{t('ui_status')}</th><th /></tr></thead>
          <tbody>
            {shown.map((e) => (
              <tr key={e.model} className="clickable" onClick={() => setEdit(e)}>
                <td><TypeBadge type={e.vtype} /></td>
                <td>{e.label} <span className="faint">{e.brand}</span></td>
                <td className="mono faint">{e.model}</td>
                <td className="hide-mobile">{t(`category_${e.category}`)}</td>
                <td className="num">{money(e.price)}</td>
                <td className="num hide-mobile faint">{e.minutes || '-'}</td>
                <td>{e.blocked ? <span className="badge danger">{t('catalog_blocked')}</span> : e.enabled ? <span className="badge ok">{t('catalog_enabled')}</span> : <span className="badge">{t('catalog_disabled')}</span>}</td>
                <td className="right"><button className="icon-btn danger" onClick={(x) => { x.stopPropagation(); setDel(e); }}><TrashIcon /></button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {edit && <EntryModal entry={edit === 'new' ? null : edit} meta={meta} onClose={() => setEdit(null)} onSaved={() => { setEdit(null); void load(); }} />}
      {del && <Confirm title={t('admin_catalog_delete')} text={t('admin_catalog_delete_text', del.label)} danger onCancel={() => setDel(null)}
        onConfirm={async () => { await call('admin.catalog.delete', { model: del.model }, t('ui_saved')); setDel(null); void load(); }} />}
    </div>
  );
}

// Delivery points ---------------------------------------------------------------------------

function PointEditor({ point, meta, onSaved, onDeleted }: { point: DeliveryPoint; meta: Meta; onSaved: () => void; onDeleted: () => void }) {
  const call = useCall();
  const [p, setP] = useState<DeliveryPoint>(JSON.parse(JSON.stringify(point)));
  const [del, setDel] = useState(false);
  useEffect(() => setP(JSON.parse(JSON.stringify(point))), [point]);
  const save = async (next: DeliveryPoint) => {
    if (await call('admin.points.save', { point: next }, t('ui_saved'))) onSaved();
  };
  const lists: Array<{ key: 'spawns' | 'waterSpawns' | 'airSpawns'; label: string }> = [
    { key: 'spawns', label: t('admin_spawns_land') },
    { key: 'waterSpawns', label: t('admin_spawns_water') },
    { key: 'airSpawns', label: t('admin_spawns_air') },
  ];
  return (
    <div className="stack s20">
      <div className="card card-body grid c2">
        <Field label={t('admin_point_label')}><input className="input" value={p.label} onChange={(e) => setP({ ...p, label: e.target.value })} /></Field>
        <Field label={t('admin_point_npc')} hint={t('admin_point_npc_hint')}><input className="input mono" value={p.npc || ''} onChange={(e) => setP({ ...p, npc: e.target.value })} /></Field>
        <Field label={t('admin_point_types')} className="span-all"><TypeChips value={p.types} onChange={(types) => setP({ ...p, types })} types={meta.types} /></Field>
        <Field label={t('admin_point_enabled')}><Toggle checked={p.enabled} onChange={(v) => setP({ ...p, enabled: v })} /></Field>
        <Field label={t('admin_point_interact')} hint={coordText(p.interact)}>
          <div className="row"><PositionButton small onPosition={(pos) => setP({ ...p, interact: pos })} />{p.interact && <button className="icon-btn" onClick={() => waypoint(p.interact!.x, p.interact!.y)}><MapIcon /></button>}</div>
        </Field>
      </div>
      {lists.map((l) => (
        <div key={l.key} className="card">
          <div className="card-head"><div className="h2">{l.label}</div><span className="faint">{p[l.key].length}</span>
            <PositionButton small label={t('admin_spawn_add')} onPosition={(pos) => setP({ ...p, [l.key]: [...p[l.key], pos] })} />
          </div>
          {p[l.key].length === 0 ? <div className="card-body faint">{t('admin_no_spawns')}</div> : p[l.key].map((s, i) => (
            <div key={i} className="list-item" style={{ cursor: 'default' }}>
              <span className="coord flex1">{coordText(s)} · {Math.round(s.w || 0)}°</span>
              <button className="icon-btn" onClick={() => waypoint(s.x, s.y)}><MapIcon /></button>
              <button className="icon-btn danger" onClick={() => setP({ ...p, [l.key]: p[l.key].filter((_, j) => j !== i) })}><TrashIcon /></button>
            </div>
          ))}
        </div>
      ))}
      <div className="row">
        <button className="btn danger" onClick={() => setDel(true)}><TrashIcon />{t('admin_point_delete')}</button>
        <div className="flex1" />
        <button className="btn primary" onClick={() => void save(p)}>{t('ui_save')}</button>
      </div>
      {del && <Confirm title={t('admin_point_delete')} text={t('admin_point_delete_text')} danger onCancel={() => setDel(false)}
        onConfirm={async () => { if (await call('admin.points.delete', { pointId: p.id }, t('ui_saved'))) onDeleted(); setDel(false); }} />}
    </div>
  );
}

function PointsAdminTab({ meta }: { meta: Meta }) {
  const call = useCall();
  const [list, setList] = useState<DeliveryPoint[] | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [newId, setNewId] = useState('');
  const [newLabel, setNewLabel] = useState('');
  const load = useCallback(async () => {
    const d = await call<DeliveryPoint[]>('admin.points.list');
    if (d) {
      setList(d);
      setSelected((s) => (s && d.some((x) => x.id === s) ? s : d[0]?.id ?? null));
    }
  }, [call]);
  useEffect(() => {
    void load();
  }, [load]);
  if (!list) return <Loading />;
  const current = list.find((p) => p.id === selected) || null;
  return (
    <div className="split" style={{ height: '100%' }}>
      <div className="pane left">
        <div style={{ padding: 12 }}><button className="btn primary block" onClick={() => setCreating(true)}><PlusIcon />{t('admin_point_add')}</button></div>
        {list.map((p) => (
          <div key={p.id} className={`list-item ${selected === p.id ? 'active' : ''}`} onClick={() => setSelected(p.id)}>
            <MapPinIcon style={{ width: 18, opacity: p.enabled ? 1 : 0.4 }} />
            <div className="flex1"><div className="h3">{p.label}</div><div className="faint" style={{ fontSize: 12 }}>{t('admin_point_summary', p.spawns.length, p.waterSpawns.length, p.airSpawns.length)}</div></div>
          </div>
        ))}
      </div>
      <div className="pane" style={{ padding: '20px 24px 40px' }}>
        {current ? <PointEditor point={current} meta={meta} onSaved={() => void load()} onDeleted={() => { setSelected(null); void load(); }} /> : <Empty title={t('admin_pick_point')} />}
      </div>
      {creating && (
        <Modal title={t('admin_point_add')} size="narrow" onClose={() => setCreating(false)}
          footer={<>
            <button className="btn ghost" onClick={() => setCreating(false)}>{t('ui_cancel')}</button>
            <PositionButton label={t('admin_point_create_here')} onPosition={async (pos) => {
              if (await call('admin.points.save', { point: { id: newId, label: newLabel, interact: pos } }, t('ui_saved'))) {
                setCreating(false);
                setSelected(newId.toLowerCase().replace(/[^a-z0-9_-]/g, ''));
                void load();
              }
            }} />
          </>}>
          <div className="stack">
            <Field label={t('admin_point_id')} hint={t('admin_point_id_desc')}><input className="input mono" value={newId} onChange={(e) => setNewId(e.target.value)} /></Field>
            <Field label={t('admin_point_label')}><input className="input" value={newLabel} onChange={(e) => setNewLabel(e.target.value)} /></Field>
          </div>
        </Modal>
      )}
    </div>
  );
}

// Audit -------------------------------------------------------------------------------------

function AuditTab() {
  const call = useCall();
  const [rows, setRows] = useState<Array<{ id: number; shopId: number; actor?: string; action: string; target?: string; createdAt: number }> | null>(null);
  const load = useCallback(async () => {
    const d = await call<typeof rows>('admin.audit', {});
    setRows(d || []);
  }, [call]);
  useEffect(() => {
    void load();
  }, [load]);
  if (!rows) return <Loading />;
  return (
    <div style={{ padding: '20px 24px 40px' }}>
      <div className="toolbar"><div className="flex1" /><button className="btn sm" onClick={() => void load()}><ArrowPathIcon />{t('ui_refresh')}</button></div>
      <div className="card">
        {rows.length === 0 ? <Empty title={t('ui_no_activity')} /> : (
          <table className="table">
            <thead><tr><th>{t('ui_date')}</th><th>{t('ui_shop')}</th><th>{t('ui_by')}</th><th>{t('ui_action')}</th><th>{t('ui_target')}</th></tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td className="faint nowrap">{dateTime(r.createdAt)}</td>
                  <td className="faint">{r.shopId || '-'}</td>
                  <td>{r.actor || '-'}</td>
                  <td>{t(`audit_${r.action.replace(/\./g, '_')}`)}</td>
                  <td className="mono faint">{r.target || ''}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

// App ---------------------------------------------------------------------------------------

export function AdminApp() {
  const [session, setSession] = useState<AdminSession | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>('shops');

  useEffect(() => {
    rpc<AdminSession>('admin.session').then((res) => {
      if (!res.ok || !res.data) {
        setError(res.message || res.error || 'unknown');
        return;
      }
      setStrings(res.data.strings);
      setCurrency(res.data.currency);
      setSession(res.data);
    }).catch(() => setError('err_network'));
  }, []);

  if (error) return <div className="loading-center"><Empty title={error} /></div>;
  if (!session) return <Loading />;

  const tabs: Array<{ key: Tab; label: string; icon: React.ComponentType<React.SVGProps<SVGSVGElement>> }> = [
    { key: 'shops', label: t('admin_shops'), icon: BuildingStorefrontIcon },
    { key: 'catalog', label: t('admin_catalog'), icon: BookOpenIcon },
    { key: 'points', label: t('admin_points_delivery'), icon: MapPinIcon },
    { key: 'audit', label: t('nav_activity'), icon: ClockIcon },
  ];

  return (
    <div className="shell" style={{ flexDirection: 'column' }}>
      <header className="topbar">
        <h1>{t('admin_panel_label')}</h1>
        <div className="spacer" />
        <div className="segmented">
          {tabs.map((x) => (
            <button key={x.key} className={tab === x.key ? 'on' : ''} onClick={() => setTab(x.key)}>
              <x.icon style={{ width: 15, height: 15 }} />{x.label}
            </button>
          ))}
        </div>
      </header>
      <div style={{ flex: 1, minHeight: 0, overflow: tab === 'shops' || tab === 'points' ? 'hidden' : 'auto', display: 'flex', flexDirection: 'column' }}>
        {tab === 'shops' && <ShopsTab meta={session.meta} />}
        {tab === 'catalog' && <CatalogTab meta={session.meta} />}
        {tab === 'points' && <PointsAdminTab meta={session.meta} />}
        {tab === 'audit' && <AuditTab />}
      </div>
    </div>
  );
}
