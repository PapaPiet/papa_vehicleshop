import React, { useCallback, useEffect, useState } from 'react';
import { ArrowPathIcon, SparklesIcon } from '@heroicons/react/24/outline';
import { useApp } from '../context';
import { t } from '../../lib/i18n';
import { money } from '../../lib/format';
import type { CatalogEntry, DisplaySpot, StockItem } from '../../lib/types';
import { Empty, Field, ListSkeleton, Modal, Plate } from '../../components/ui';
import { ConditionMeter, StatusBadge, TypeBadge } from '../../components/vs';

function FillModal(props: { spot: DisplaySpot; onClose: () => void; onDone: () => void }) {
  const { call } = useApp();
  const [list, setList] = useState<StockItem[] | null>(null);
  useEffect(() => {
    void call<StockItem[]>('stock.list', { statuses: ['storage'] }).then((d) => setList((d || []).filter((v) => props.spot.types.includes(v.vtype))));
  }, [call, props.spot.types]);
  return (
    <Modal title={t('ui_fill_spot', props.spot.label || t('display_number', props.spot.id))} onClose={props.onClose}>
      {!list ? <ListSkeleton rows={3} /> : list.length === 0 ? (
        <Empty title={t('display_no_candidates')} text={t('display_drive_on_hint')} />
      ) : (
        <div className="card">
          {list.map((v) => (
            <div key={v.id} className="list-item" onClick={async () => {
              if (await call('stock.display', { stockId: v.id, displayId: props.spot.id }, t('ui_saved'))) props.onDone();
            }}>
              <TypeBadge type={v.vtype} />
              <div className="flex1">
                <div className="h3">{v.label}</div>
                <ConditionMeter condition={v.condition} compact />
              </div>
              <Plate plate={v.plate} />
              <b>{money(v.price)}</b>
            </div>
          ))}
        </div>
      )}
    </Modal>
  );
}

function ShowcaseModal(props: { spot: DisplaySpot; onClose: () => void; onDone: () => void }) {
  const { call } = useApp();
  const [catalog, setCatalog] = useState<CatalogEntry[] | null>(null);
  const [model, setModel] = useState(props.spot.showcase?.model || '');
  useEffect(() => {
    void call<CatalogEntry[]>('catalog.list').then((d) => setCatalog((d || []).filter((e) => props.spot.types.includes(e.vtype))));
  }, [call, props.spot.types]);
  return (
    <Modal title={t('showcase_set_model')} size="narrow" onClose={props.onClose}
      footer={<>
        <button className="btn ghost" onClick={props.onClose}>{t('ui_cancel')}</button>
        <button className="btn primary" onClick={async () => {
          if (await call('displays.showcase', { displayId: props.spot.id, model }, t('ui_saved'))) props.onDone();
        }}>{t('ui_save')}</button>
      </>}>
      {!catalog ? <ListSkeleton rows={2} /> : (
        <Field label={t('ui_model')} hint={t('ui_showcase_hint')}>
          <select className="select" value={model} onChange={(e) => setModel(e.target.value)}>
            <option value="">{t('showcase_none')}</option>
            {catalog.map((e) => <option key={e.model} value={e.model}>{e.label} · {money(e.price)}</option>)}
          </select>
        </Field>
      )}
    </Modal>
  );
}

export function DisplaysView() {
  const { call, go, session } = useApp();
  const [spots, setSpots] = useState<DisplaySpot[] | null>(null);
  const [fill, setFill] = useState<DisplaySpot | null>(null);
  const [showcase, setShowcase] = useState<DisplaySpot | null>(null);
  const canManage = session.flags.displayManage;

  const load = useCallback(async () => {
    const d = await call<DisplaySpot[]>('displays.list');
    setSpots(d || []);
  }, [call]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!spots) return <ListSkeleton rows={6} />;
  if (spots.length === 0) return <Empty title={t('ui_no_spots')} text={t('ui_no_spots_text')} />;

  return (
    <div className="stack">
      <div className="toolbar">
        <span className="muted flex1">{t('ui_spots_hint')}</span>
        <button className="btn sm" onClick={() => void load()}><ArrowPathIcon />{t('ui_refresh')}</button>
      </div>
      <div className="spots">
        {spots.map((s) => {
          const v = s.vehicle;
          return (
            <div key={s.id} className={`spot ${v || s.showcase ? 'taken' : ''}`}>
              <div className="row between">
                <b className="ellipsis">{s.label || t('display_number', s.id)}</b>
                <span className="pill">{t(`display_kind_${s.kind}`)}</span>
              </div>
              <div className="types">{s.types.map((ty) => <span key={ty} className="pill">{t(`vtype_${ty}`)}</span>)}</div>
              {v ? (
                <>
                  <div className="row" style={{ cursor: 'pointer' }} onClick={() => go({ name: 'stock', open: v.id })}>
                    <TypeBadge type={v.vtype} />
                    <div className="flex1">
                      <div className="h3 ellipsis">{v.label}</div>
                      <div className="faint" style={{ fontSize: 12 }}>{money(v.price)}</div>
                    </div>
                    <StatusBadge status={v.status} />
                  </div>
                  <ConditionMeter condition={v.condition} compact />
                </>
              ) : s.kind === 'showcase' ? (
                <>
                  {s.showcase ? (
                    <div className="row"><SparklesIcon style={{ width: 16 }} /><span className="flex1 ellipsis">{s.showcase.label}</span><span className="faint">{money(s.showcase.price)}</span></div>
                  ) : <span className="faint">{t('ui_showcase_empty')}</span>}
                  {canManage && <button className="btn sm" onClick={() => setShowcase(s)}>{t('showcase_set_model')}</button>}
                </>
              ) : (
                <>
                  <span className="faint">{t('display_free')}</span>
                  {canManage && <button className="btn sm primary" onClick={() => setFill(s)}>{t('ui_fill')}</button>}
                </>
              )}
            </div>
          );
        })}
      </div>
      {fill && <FillModal spot={fill} onClose={() => setFill(null)} onDone={() => { setFill(null); void load(); }} />}
      {showcase && <ShowcaseModal spot={showcase} onClose={() => setShowcase(null)} onDone={() => { setShowcase(null); void load(); }} />}
    </div>
  );
}
