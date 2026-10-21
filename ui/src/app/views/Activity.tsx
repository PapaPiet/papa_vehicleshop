import React, { useCallback, useEffect, useState } from 'react';
import { useApp } from '../context';
import { t } from '../../lib/i18n';
import { dateTime } from '../../lib/format';
import { Empty, ListSkeleton } from '../../components/ui';

interface AuditRow { id: number; actor?: string; action: string; target?: string; createdAt: number }

export function ActivityView() {
  const { call } = useApp();
  const [rows, setRows] = useState<AuditRow[] | null>(null);
  const load = useCallback(async () => {
    const d = await call<AuditRow[]>('audit.list', { limit: 150 });
    setRows(d || []);
  }, [call]);
  useEffect(() => {
    void load();
  }, [load]);
  if (!rows) return <ListSkeleton rows={8} />;
  if (rows.length === 0) return <Empty title={t('ui_no_activity')} />;
  return (
    <div className="card">
      <table className="table">
        <thead><tr><th>{t('ui_date')}</th><th>{t('ui_by')}</th><th>{t('ui_action')}</th><th className="hide-mobile">{t('ui_target')}</th></tr></thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.id}>
              <td className="faint nowrap">{dateTime(r.createdAt)}</td>
              <td>{r.actor || '-'}</td>
              <td>{t(`audit_${r.action.replace(/\./g, '_')}`)}</td>
              <td className="hide-mobile mono faint">{r.target || ''}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
