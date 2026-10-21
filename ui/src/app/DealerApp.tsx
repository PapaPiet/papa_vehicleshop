import React, { useCallback, useEffect, useState } from 'react';
import {
  ChartBarSquareIcon,
  ArchiveBoxIcon,
  RectangleGroupIcon,
  ShoppingCartIcon,
  TruckIcon,
  BanknotesIcon,
  ArrowsRightLeftIcon,
  ReceiptPercentIcon,
  BuildingLibraryIcon,
  UserGroupIcon,
  Cog6ToothIcon,
  ClockIcon,
  BuildingStorefrontIcon,
  ChevronUpDownIcon,
} from '@heroicons/react/24/outline';
import { rpc, rpcCache } from '../lib/rpc';
import { hasText, setStrings, t } from '../lib/i18n';
import { FeedbackLayer } from '../shared/FeedbackUi';
import { feedbackErrorText, getFeedbackTexts, notifyAppLoading, notifyAppReady, setFeedbackTexts, type FeedbackTexts } from '../shared/uiFeedback';
import { setCurrency, setDateTimeFormat } from '../lib/format';
import type { Session } from '../lib/types';
import { AppProvider, View } from './context';
import { initials, LoadError, Loading } from '../components/ui';
import { DashboardView } from './views/Dashboard';
import { StockView } from './views/Stock';
import { DisplaysView } from './views/Displays';
import { OrderView } from './views/Order';
import { DeliveriesView } from './views/Deliveries';
import { SalesView } from './views/Sales';
import { TradeInsView } from './views/TradeIns';
import { FinanceView } from './views/Finance';
import { AccountView } from './views/Account';
import { TeamView } from './views/Team';
import { SettingsView } from './views/Settings';
import { ActivityView } from './views/Activity';

type NavKey = View['name'];

/** Texte fuer Ladeanzeigen und Rueckmeldungen aus den Sprachdateien (Schluessel der App -> shared/uiFeedback). */
const FEEDBACK_KEYS: Record<keyof FeedbackTexts, string> = {
  fbLoading: 'ui_loading',
  fbSlow: 'fb_slow',
  fbRetry: 'fb_retry',
  fbReload: 'fb_reload',
  fbSaved: 'ui_saved',
  fbDeleted: 'fb_deleted',
  fbSent: 'fb_sent',
  fbEmpty: 'fb_empty',
  fbLoadFailed: 'fb_load_failed',
  fbDismiss: 'ui_close',
  errForbidden: 'err_no_permission',
  errServerOffline: 'err_server_offline',
  errTimeout: 'err_timeout',
  errPlayerOffline: 'err_player_offline',
  errWebUnsupported: 'err_web_unsupported',
  errUnverifiedResource: 'err_unverified_resource',
  errRateLimited: 'err_rate_limited',
  errUnknownCallback: 'err_unknown_callback',
  errGeneric: 'err_unknown',
};

function applyFeedbackTexts() {
  const out: Partial<FeedbackTexts> = {};
  for (const [k, key] of Object.entries(FEEDBACK_KEYS) as Array<[keyof FeedbackTexts, string]>) {
    if (hasText(key)) out[k] = t(key);
  }
  setFeedbackTexts(out);
}

function errorLabel(error: string): string {
  if (error.startsWith('err_') && hasText(error)) return t(error);
  if (hasText(`err_${error}`)) return t(`err_${error}`);
  if (error === 'err_network') return feedbackErrorText('server_offline', getFeedbackTexts());
  if (/^[a-z_]+$/.test(error)) return feedbackErrorText(error, getFeedbackTexts());
  return error;
}

export function DealerApp() {
  const [session, setSession] = useState<Session | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [shopId, setShopId] = useState<number | null>(null);
  const [history, setHistory] = useState<View[]>([{ name: 'dashboard' }]);
  const [shopPicker, setShopPicker] = useState(false);
  const view = history[history.length - 1];

  const loadSession = useCallback(async (wanted?: number | null) => {
    let res;
    try {
      res = await rpc<Session>('session', wanted ? { shopId: wanted } : {});
    } catch {
      setError('err_network');
      notifyAppReady();
      return;
    }
    if (!res.ok || !res.data) {
      setError(res.message || res.error || 'unknown');
      notifyAppReady();
      return;
    }
    const data = res.data;
    void rpcCache.setIdentity({
      identifier: data.actor?.id ? `${data.actor.id}|${data.shop.id}|${data.actor.grade ?? ''}|${data.flags.boss ? 1 : 0}` : '',
      version: data.resourceVersion ?? '',
      enabled: data.uiCache !== false,
    });
    setStrings(data.strings);
    applyFeedbackTexts();
    setDateTimeFormat(data.dateTimeFormat);
    setCurrency(data.settings.currency);
    setError(null);
    setShopId(data.shop.id);
    setSession(data);
    notifyAppReady();
  }, []);

  useEffect(() => {
    notifyAppLoading();
    void loadSession(null);
  }, [loadSession]);

  const go = useCallback((v: View) => {
    setHistory((h) => {
      const top = h[h.length - 1];
      if (JSON.stringify(top) === JSON.stringify(v)) return h;
      return [...h.slice(-30), v];
    });
  }, []);
  const back = useCallback(() => setHistory((h) => (h.length > 1 ? h.slice(0, -1) : h)), []);
  const navTo = useCallback((v: View) => setHistory([v]), []);
  const reload = useCallback(() => loadSession(shopId), [loadSession, shopId]);

  if (error) {
    return (
      <div className="shell" style={{ display: 'grid', placeItems: 'center' }}>
        <LoadError message={errorLabel(error)} onRetry={() => { setError(null); void loadSession(shopId); }} />
        <FeedbackLayer />
      </div>
    );
  }
  if (!session) {
    return (
      <div className="shell" style={{ display: 'grid', placeItems: 'center' }}>
        <Loading />
        <FeedbackLayer />
      </div>
    );
  }

  const f = session.flags;
  const navItems: Array<{ key: NavKey; label: string; icon: React.ComponentType<React.SVGProps<SVGSVGElement>>; show: boolean; section?: string }> = [
    { key: 'dashboard', label: t('nav_dashboard'), icon: ChartBarSquareIcon, show: true },
    { key: 'stock', label: t('nav_stock'), icon: ArchiveBoxIcon, show: f.stockView },
    { key: 'displays', label: t('nav_displays'), icon: RectangleGroupIcon, show: true },
    { key: 'order', label: t('nav_order'), icon: ShoppingCartIcon, show: f.order },
    { key: 'deliveries', label: t('nav_deliveries'), icon: TruckIcon, show: f.stockView },
    { key: 'sales', label: t('nav_sales'), icon: BanknotesIcon, show: true, section: t('nav_section_business') },
    { key: 'tradeins', label: t('nav_tradeins'), icon: ArrowsRightLeftIcon, show: f.tradeIn },
    { key: 'finance', label: t('nav_finance'), icon: ReceiptPercentIcon, show: f.finance },
    { key: 'account', label: t('nav_account'), icon: BuildingLibraryIcon, show: f.accountView },
    { key: 'team', label: t('nav_team'), icon: UserGroupIcon, show: true, section: t('nav_section_admin') },
    { key: 'settings', label: t('nav_settings'), icon: Cog6ToothIcon, show: f.settings },
    { key: 'activity', label: t('nav_activity'), icon: ClockIcon, show: f.auditView },
  ];
  const visible = navItems.filter((n) => n.show);

  const content = (() => {
    switch (view.name) {
      case 'dashboard':
        return <DashboardView />;
      case 'stock':
        return <StockView key={view.open ?? 0} initialFilter={view.filter} openId={view.open} />;
      case 'displays':
        return <DisplaysView />;
      case 'order':
        return <OrderView />;
      case 'deliveries':
        return <DeliveriesView />;
      case 'sales':
        return <SalesView />;
      case 'tradeins':
        return <TradeInsView />;
      case 'finance':
        return <FinanceView />;
      case 'account':
        return <AccountView />;
      case 'team':
        return <TeamView />;
      case 'settings':
        return <SettingsView />;
      case 'activity':
        return <ActivityView />;
      default:
        return null;
    }
  })();

  const current = navItems.find((n) => n.key === view.name);

  return (
    <AppProvider key={session.shop.id} session={session} view={view} go={go} back={back} reloadSession={reload}>
      <div className="shell">
        <FeedbackLayer />
        <aside className="sidebar">
          <button className="brand" style={{ background: 'none', border: 0, cursor: session.shops.length > 1 ? 'pointer' : 'default', textAlign: 'left' }}
            onClick={() => session.shops.length > 1 && setShopPicker((v) => !v)}>
            <div className="brand-mark"><BuildingStorefrontIcon /></div>
            <div style={{ minWidth: 0, flex: 1 }}>
              <div className="brand-title">{t('app_name')}</div>
              <div className="brand-sub">{session.shop.label}</div>
            </div>
            {session.shops.length > 1 && <ChevronUpDownIcon style={{ width: 16, height: 16, color: 'var(--text-3)' }} />}
          </button>
          {shopPicker && (
            <div className="card" style={{ marginBottom: 10 }}>
              {session.shops.map((s) => (
                <div key={s.id} className={`list-item ${s.id === session.shop.id ? 'active' : ''}`}
                  onClick={() => { setShopPicker(false); navTo({ name: 'dashboard' }); void loadSession(s.id); }}>
                  <BuildingStorefrontIcon style={{ width: 16, height: 16 }} />
                  <span className="ellipsis">{s.label}</span>
                </div>
              ))}
            </div>
          )}
          <nav className="nav">
            {visible.map((n) => (
              <React.Fragment key={n.key}>
                {n.section && <div className="nav-section">{n.section}</div>}
                <button className={`nav-item ${view.name === n.key ? 'active' : ''}`} onClick={() => navTo({ name: n.key } as View)}>
                  <n.icon />
                  <span>{n.label}</span>
                </button>
              </React.Fragment>
            ))}
          </nav>
          <div className="sidebar-foot">
            <div className="avatar">{initials(session.actor.name)}</div>
            <div className="who">
              <b>{session.actor.name}</b>
              <span>{session.actor.gradeLabel || t(`shoptype_${session.shop.type}`)}</span>
            </div>
          </div>
        </aside>
        <main className="main">
          <header className="topbar">
            <h1>{current?.label ?? t('app_name')}</h1>
            <div className="spacer" />
            {session.shop.type === 'mixed' && (
              <span className={`badge ${session.shop.npcActive ? 'warn' : 'ok'}`}>
                {session.shop.npcActive ? t('ui_npc_active') : t('ui_staff_active')}
              </span>
            )}
          </header>
          <div className="content">{content}</div>
        </main>
        <nav className="mobile-nav">
          {visible.slice(0, 5).map((n) => (
            <button key={n.key} className={view.name === n.key ? 'active' : ''} onClick={() => navTo({ name: n.key } as View)}>
              <n.icon />
              {n.label}
            </button>
          ))}
        </nav>
      </div>
    </AppProvider>
  );
}
