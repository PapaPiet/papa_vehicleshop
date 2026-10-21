import React, { createContext, useCallback, useContext } from 'react';
import { rpc, RpcResult } from '../lib/rpc';
import { t } from '../lib/i18n';
import { useToast } from '../components/ui';
import { currentActionButton } from '../shared/uiFeedback';
import type { Session } from '../lib/types';

export type View =
  | { name: 'dashboard' }
  | { name: 'stock'; filter?: string; open?: number }
  | { name: 'displays' }
  | { name: 'order' }
  | { name: 'deliveries' }
  | { name: 'sales' }
  | { name: 'tradeins' }
  | { name: 'finance' }
  | { name: 'account' }
  | { name: 'team' }
  | { name: 'settings' }
  | { name: 'activity' };

interface Ctx {
  session: Session;
  view: View;
  go: (v: View) => void;
  back: () => void;
  reloadSession: () => Promise<void>;
  /** RPC call that toasts errors and returns data or null. onUpdate: fresh data from a background refresh of the cache. */
  call: <T = unknown>(
    action: string,
    payload?: Record<string, unknown>,
    okText?: string,
    opts?: { onUpdate?: (data: T) => void }
  ) => Promise<T | null>;
  callRaw: <T = unknown>(action: string, payload?: Record<string, unknown>) => Promise<RpcResult<T>>;
}

const AppCtx = createContext<Ctx | null>(null);

export function AppProvider(props: {
  session: Session;
  view: View;
  go: (v: View) => void;
  back: () => void;
  reloadSession: () => Promise<void>;
  children: React.ReactNode;
}) {
  const toast = useToast();
  const shopId = props.session.shop.id;
  const callRaw = useCallback(<T,>(action: string, payload: Record<string, unknown> = {}) => rpc<T>(action, { shopId, ...payload }), [shopId]);
  const call = useCallback(
    async <T,>(
      action: string,
      payload: Record<string, unknown> = {},
      okText?: string,
      opts?: { onUpdate?: (data: T) => void }
    ): Promise<T | null> => {
      // Button der Benutzeraktion (nur waehrend des Klicks bekannt): "Erneut versuchen" klickt ihn noch einmal
      const button = currentActionButton();
      const retry = button
        ? () => {
            if (button.isConnected) button.click();
          }
        : undefined;
      const onUpdate = opts?.onUpdate;
      let res: RpcResult<T>;
      try {
        res = await rpc<T>(action, { shopId, ...payload }, {
          onUpdate: onUpdate
            ? (fresh) => {
                if (fresh.ok) onUpdate((fresh.data ?? (true as unknown)) as T);
              }
            : undefined,
        });
      } catch {
        toast('error', t('err_network'), retry);
        return null;
      }
      if (!res.ok) {
        toast('error', res.message || t(`err_${res.error}`) || String(res.error), retry);
        return null;
      }
      if (okText) toast('ok', okText);
      return (res.data ?? (true as unknown)) as T;
    },
    [toast, shopId],
  );
  return (
    <AppCtx.Provider value={{ session: props.session, view: props.view, go: props.go, back: props.back, reloadSession: props.reloadSession, call, callRaw }}>
      {props.children}
    </AppCtx.Provider>
  );
}

export function useApp(): Ctx {
  const ctx = useContext(AppCtx);
  if (!ctx) throw new Error('AppProvider missing');
  return ctx;
}
