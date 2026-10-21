import React, { useCallback, useEffect, useState } from 'react';
import { ShieldCheckIcon } from '@heroicons/react/24/outline';
import { useApp } from '../context';
import { t } from '../../lib/i18n';
import { relative } from '../../lib/format';
import { Empty, ListSkeleton } from '../../components/ui';

interface Member { playerId?: string; name: string; gradeLabel?: string; gradeName?: string; online?: boolean; onDuty?: boolean; lastSeenMs?: number }
interface PolicyData { policy: Record<string, number>; grades: Array<{ level: number; name: string }> }

export function TeamView() {
  const { call, session } = useApp();
  const [members, setMembers] = useState<Member[] | null>(null);
  const [policy, setPolicy] = useState<PolicyData | null>(null);
  const [draft, setDraft] = useState<Record<string, number>>({});

  const load = useCallback(async () => {
    const [m, p] = await Promise.all([call<Member[]>('staff.list'), call<PolicyData>('policy.get')]);
    setMembers(m || []);
    if (p) {
      setPolicy(p);
      setDraft(p.policy);
    }
  }, [call]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!members || !policy) return <ListSkeleton rows={6} />;
  const boss = session.flags.boss;
  const grades = policy.grades.length > 0 ? policy.grades : Array.from({ length: 6 }, (_, i) => ({ level: i, name: String(i) }));

  return (
    <div className="grid c2" style={{ alignItems: 'start' }}>
      <div className="card">
        <div className="card-head"><div className="h2">{t('ui_team')}</div><span className="faint">{members.filter((m) => m.online).length}/{members.length}</span></div>
        {members.length === 0 ? <Empty title={t('ui_no_team')} /> : members.map((m, i) => (
          <div key={m.playerId || i} className="list-item" style={{ cursor: 'default' }}>
            <span className={`badge ${m.online ? (m.onDuty === false ? 'warn' : 'ok') : ''}`}>{m.online ? (m.onDuty === false ? t('ui_off_duty') : t('ui_on_duty')) : t('ui_offline')}</span>
            <div className="flex1"><div className="h3">{m.name}</div><div className="faint" style={{ fontSize: 12 }}>{m.gradeLabel || m.gradeName || ''}</div></div>
            {!m.online && m.lastSeenMs ? <span className="faint" style={{ fontSize: 12 }}>{relative(m.lastSeenMs)}</span> : null}
          </div>
        ))}
      </div>
      <div className="card">
        <div className="card-head"><ShieldCheckIcon style={{ width: 18 }} /><div className="h2">{t('ui_permissions')}</div></div>
        <div className="card-body stack s8">
          <span className="faint" style={{ fontSize: 12 }}>{t('ui_permissions_hint')}</span>
          {session.meta.policyKeys.map((key) => (
            <div key={key} className="row between">
              <span>{t(`policy_${key}`)}</span>
              <select className="select" style={{ width: 170 }} disabled={!boss} value={draft[key] ?? 0}
                onChange={(e) => setDraft((d) => ({ ...d, [key]: Number(e.target.value) }))}>
                {grades.map((g) => <option key={g.level} value={g.level}>{t('ui_from_grade', g.name, g.level)}</option>)}
                <option value={99}>{t('ui_boss_only')}</option>
              </select>
            </div>
          ))}
          {boss && (
            <button className="btn primary" style={{ marginTop: 8 }} onClick={async () => {
              if (await call('policy.save', { policy: draft }, t('ui_saved'))) void load();
            }}>{t('ui_save')}</button>
          )}
        </div>
      </div>
    </div>
  );
}
