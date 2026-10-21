/**
 * Slack Channels Onboard — one row per Slack channel the bot is in (or has a binding for).
 *
 * Configured rows: edit workspace directory, activation, thread_follow.
 * Unconfigured rows: one-click Onboard (workspace + agent + private memory + binding).
 * Settings: the background detector mode and defaults for new channels.
 *
 * Everything goes through this app's owner-only routes under
 * /api/apps/slack-channels-onboard, which reuse the gateway's own config writer.
 */
import { useAppApi } from '@kirocrew/app-sdk'
import { Badge, Btn, Card, CardTitle, EmptyState, Input, PageHeader, StatCard, Toggle } from '@kirocrew/app-sdk/ui'
import { useCallback, useEffect, useState } from 'react'
import { t } from './i18n'

const BASE = '/api/apps/slack-channels-onboard'
const ACTIVATIONS = ['mention', 'always', 'observe', 'review', 'off'] as const

interface Row {
  id: string
  name: string
  bot_member: boolean
  configured: boolean
  agent?: string
  activation?: string
  thread_follow?: boolean
  workspace?: string
  workspace_dir?: string
  memory_store?: string
}

interface Settings {
  mode: 'auto' | 'notify' | 'off'
  workspace_root: string
  activation: string
  thread_follow: boolean
  require_owner_member: boolean
  dedicated_memory: boolean
  poll_secs: number
}

interface ListResponse {
  channels: Row[]
  settings: Settings
  slack_error: string
}

function Select({ value, options, onChange, label }: { value: string; options: readonly string[]; onChange: (v: string) => void; label: string }) {
  return (
    <select
      aria-label={label}
      className="bg-[var(--bg-input,transparent)] border border-[var(--border)] rounded px-2 py-1 text-sm"
      value={value}
      onChange={(e) => onChange(e.target.value)}
    >
      {options.map((o) => (
        <option key={o} value={o}>{o}</option>
      ))}
    </select>
  )
}

function ConfiguredRow({ row, open, canOpen, onSaved, onError }: { row: Row; open: boolean; canOpen: boolean; onSaved: () => void; onError: (m: string) => void }) {
  const api = useAppApi()
  const [dir, setDir] = useState(row.workspace_dir || '')
  const [activation, setActivation] = useState(row.activation || 'mention')
  const [follow, setFollow] = useState(row.thread_follow ?? true)
  const [busy, setBusy] = useState(false)
  const dirty = dir !== (row.workspace_dir || '') || activation !== row.activation || follow !== row.thread_follow

  const save = async () => {
    setBusy(true)
    try {
      await api.post(`${BASE}/reconfigure`, {
        channel_id: row.id,
        workspace_dir: dir !== (row.workspace_dir || '') ? dir : undefined,
        activation: activation !== row.activation ? activation : undefined,
        thread_follow: follow !== row.thread_follow ? follow : undefined,
      })
      onSaved()
    } catch (e) {
      onError(String(e))
    } finally {
      setBusy(false)
    }
  }

  const setOpen = async (v: boolean) => {
    if (v && !window.confirm(t.openConfirm(row.name || row.id))) return
    setBusy(true)
    try {
      await api.put(`${BASE}/open`, { channel_id: row.id, open: v })
      onSaved()
    } catch (e) {
      onError(String(e))
    } finally {
      setBusy(false)
    }
  }

  const unbind = async () => {
    if (!window.confirm(t.unbindConfirm(row.name || row.id))) return
    setBusy(true)
    try {
      await api.post(`${BASE}/unbind`, { channel_id: row.id })
      onSaved()
    } catch (e) {
      onError(String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <tr className="border-t border-[var(--border)] align-top" data-testid={`row-${row.id}`}>
      <td className="py-2 pr-3">
        <div className="font-medium">#{row.name || row.id}</div>
        <div className="text-xs text-muted">{row.id}</div>
        {!row.bot_member && (
          <div className="mt-1 flex items-center gap-2">
            <Badge variant="warn">{t.botLeft}</Badge>
            <Btn danger disabled={busy} onClick={unbind}>{t.unbind}</Btn>
          </div>
        )}
      </td>
      <td className="py-2 pr-3">
        <div className="font-mono text-sm whitespace-nowrap">{row.agent || t.defaultAgent}</div>
        <div className="text-xs text-muted">memory: {row.memory_store || '—'}</div>
      </td>
      <td className="py-2 pr-3 w-[38%] min-w-[320px]">
        <Input aria-label={t.workspaceOf(row.name || row.id)} title={dir} className="w-full font-mono text-xs" value={dir} onChange={(e) => setDir(e.target.value)} disabled={!row.agent} />
      </td>
      <td className="py-2 pr-3">
        <Select label="Activation" value={activation} options={ACTIVATIONS} onChange={setActivation} />
      </td>
      <td className="py-2 pr-3">
        <Toggle checked={follow} onChange={setFollow} label="thread_follow" />
      </td>
      {canOpen && (
        <td className="py-2 pr-3">
          <Toggle checked={open} onChange={(v) => { void setOpen(v) }} label={t.openToggle(row.name || row.id)} />
        </td>
      )}
      <td className="py-2 w-[72px]">
        {dirty && <Btn primary disabled={busy} onClick={save}>{busy ? t.saving : t.save}</Btn>}
      </td>
    </tr>
  )
}

function PendingRow({ row, settings, onDone, onError }: { row: Row; settings: Settings; onDone: () => void; onError: (m: string) => void }) {
  const api = useAppApi()
  const [busy, setBusy] = useState(false)
  const onboard = async () => {
    setBusy(true)
    try {
      await api.post(`${BASE}/onboard`, { channel_id: row.id, channel_name: row.name })
      onDone()
    } catch (e) {
      onError(String(e))
    } finally {
      setBusy(false)
    }
  }
  return (
    <tr className="border-t border-[var(--border)]" data-testid={`pending-${row.id}`}>
      <td className="py-2 pr-3">
        <div className="font-medium">#{row.name || row.id}</div>
        <div className="text-xs text-muted">{row.id}</div>
      </td>
      <td className="py-2 pr-3 text-sm text-muted">
        <span className="font-mono">{t.pendingPlan(row.name || row.id, settings.workspace_root, settings.dedicated_memory)}</span>
      </td>
      <td className="py-2">
        <Btn primary disabled={busy} onClick={onboard}>{busy ? t.creating : 'Onboard'}</Btn>
      </td>
    </tr>
  )
}

// ------------------------------------------------------- people (slice 4)

interface Member { slack_id: string; name: string; display?: string }
interface PeopleChannel { id: string; name: string; agent: string; workspace_dir: string; maintainers: string[]; commands: string[]; open: boolean; programs: string[] }
interface CommandDef { id: string; label: string; example: string }
interface People {
  owner: { slack_id: string; display: string }
  members: Member[]
  channels: PeopleChannel[]
  command_catalog: CommandDef[]
  roles_path: string
  roles_error: string
  capabilities?: Caps
}
interface Caps { members: boolean; maintainers: boolean; commands: boolean; programs: boolean; open_channel: boolean; confinement: boolean; any: boolean }

const NO_CAPS: Caps = { members: false, maintainers: false, commands: false, programs: false, open_channel: false, confinement: false, any: false }

const label = (m: Member | undefined, id: string) => (m && (m.display || m.name)) || id

function MembersCard({ people, onSaved, onError }: { people: People; onSaved: (msg: string) => void; onError: (m: string) => void }) {
  const api = useAppApi()
  const [newId, setNewId] = useState('')
  const [busy, setBusy] = useState(false)

  const save = async (members: Member[]) => {
    setBusy(true)
    try {
      const r = await api.put<{ hot_applied: boolean }>(`${BASE}/members`, { members: members.map(({ slack_id, name }) => ({ slack_id, name })) })
      onSaved(r.hot_applied ? t.savedLive : t.savedNeedsRestart)
    } catch (e) {
      onError(String(e))
    } finally {
      setBusy(false)
    }
  }

  const add = async () => {
    const id = newId.trim().toUpperCase()
    if (!id) return
    setBusy(true)
    try {
      const u = await api.post<{ slack_id: string; name: string }>(`${BASE}/resolve-user`, { slack_id: id })
      setNewId('')
      await save([...people.members, { slack_id: u.slack_id, name: u.name }])
    } catch (e) {
      onError(String(e))
      setBusy(false)
    }
  }

  const remove = (id: string) => {
    const m = people.members.find((x) => x.slack_id === id)
    if (!window.confirm(t.removeMemberConfirm(label(m, id)))) return
    void save(people.members.filter((x) => x.slack_id !== id))
  }

  return (
    <Card>
      <CardTitle>{t.membersTitle}</CardTitle>
      <ul className="text-xs text-muted mb-2 list-disc pl-5 space-y-0.5">
        {t.membersHelp.map((x) => <li key={x}>{x}</li>)}
      </ul>
      <table className="w-full text-left text-sm"><tbody>
        <tr className="border-t border-[var(--border)]">
          <td className="py-2 pr-3">{people.owner.display || people.owner.slack_id}</td>
          <td className="py-2 pr-3 font-mono text-xs text-muted">{people.owner.slack_id}</td>
          <td className="py-2"><Badge variant="ok">{t.ownerBadge}</Badge></td>
        </tr>
        {people.members.map((m) => (
          <tr key={m.slack_id} className="border-t border-[var(--border)]" data-testid={`member-${m.slack_id}`}>
            <td className="py-2 pr-3">{label(m, m.slack_id)}</td>
            <td className="py-2 pr-3 font-mono text-xs text-muted">{m.slack_id}</td>
            <td className="py-2"><Btn disabled={busy} onClick={() => remove(m.slack_id)}>{t.remove}</Btn></td>
          </tr>
        ))}
      </tbody></table>
      <div className="mt-3 flex gap-2 items-center">
        <Input aria-label={t.addMemberLabel} placeholder={t.addMemberPlaceholder} value={newId} onChange={(e) => setNewId(e.target.value)} />
        <Btn primary={!!newId.trim()} disabled={busy || !newId.trim()} onClick={add}>{busy ? t.saving : t.addMember}</Btn>
      </div>
      <p className="text-xs text-muted mt-2">{t.memberIdHint}</p>
    </Card>
  )
}

function ChannelRoleRow({ ch, members, catalog, caps, onSaved, onError }: { ch: PeopleChannel; members: Member[]; catalog: CommandDef[]; caps: Caps; onSaved: (msg: string) => void; onError: (m: string) => void }) {
  const api = useAppApi()
  const [busy, setBusy] = useState(false)
  const [pick, setPick] = useState('')
  const [expanded, setExpanded] = useState(false)
  const byId = new Map(members.map((m) => [m.slack_id, m]))
  const candidates = members.filter((m) => !ch.maintainers.includes(m.slack_id))
  const hasRules = ch.commands.length > 0 || ch.programs.length > 0

  const save = async (ids: string[]) => {
    setBusy(true)
    try {
      await api.put(`${BASE}/maintainers`, { channel_id: ch.id, maintainers: ids })
      onSaved(t.maintainersSaved)
    } catch (e) {
      onError(String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="border-t border-[var(--border)] py-2" data-testid={`maint-${ch.id}`}>
      <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
        <div className="min-w-[180px]">
          <div className="font-medium">#{ch.name || ch.id}</div>
          <div className="text-xs text-muted font-mono truncate max-w-[260px]" title={ch.workspace_dir}>{ch.workspace_dir || t.noWorkspace}</div>
        </div>
        <div className="flex flex-wrap gap-1 flex-1 min-w-[160px]">
          {ch.maintainers.map((id) => (
            <span key={id} className="inline-flex items-center gap-1">
              <Badge variant="aim">{label(byId.get(id), id)}</Badge>
              <button type="button" aria-label={t.removeMaintainer(label(byId.get(id), id))} className="text-xs text-muted hover:text-danger" disabled={busy}
                onClick={() => save(ch.maintainers.filter((x) => x !== id))}>✕</button>
            </span>
          ))}
          {ch.maintainers.length === 0 && <span className="text-xs text-muted">{t.noMaintainer}</span>}
        </div>
        {caps.commands && (ch.maintainers.length > 0 || hasRules) && (
          <button type="button" className="text-xs text-accent hover:underline" aria-expanded={expanded}
            onClick={() => setExpanded((v) => !v)} data-testid={`maint-toggle-${ch.id}`}>
            {t.rulesSummary(ch.commands.length, ch.programs.length, expanded)}
          </button>
        )}
        <div className="flex gap-2 items-center">
          <select aria-label={t.addMaintainerLabel(ch.name || ch.id)} className="bg-[var(--bg-input,transparent)] border border-[var(--border)] rounded px-2 py-1 text-sm"
            value={pick} onChange={(e) => setPick(e.target.value)} disabled={busy || candidates.length === 0 || !ch.workspace_dir}>
            <option value="">{candidates.length ? t.addMaintainer : t.noMoreMembers}</option>
            {candidates.map((m) => <option key={m.slack_id} value={m.slack_id}>{label(m, m.slack_id)}</option>)}
          </select>
          {pick && <Btn primary disabled={busy} onClick={() => { void save([...ch.maintainers, pick]); setPick('') }}>{t.add}</Btn>}
        </div>
      </div>
      {expanded && caps.commands && <CommandsPanel ch={ch} catalog={catalog} caps={caps} onSaved={onSaved} onError={onError} />}
    </div>
  )
}

function CommandsPanel({ ch, catalog, caps, onSaved, onError }: { ch: PeopleChannel; catalog: CommandDef[]; caps: Caps; onSaved: (msg: string) => void; onError: (m: string) => void }) {
  const api = useAppApi()
  const [sel, setSel] = useState<string[]>(ch.commands)
  const [busy, setBusy] = useState(false)
  const dirty = sel.slice().sort().join(',') !== ch.commands.slice().sort().join(',')
  const toggle = (id: string, on: boolean) => setSel((cur) => (on ? [...cur.filter((x) => x !== id), id] : cur.filter((x) => x !== id)))
  const save = async () => {
    if (sel.includes('deploy') && !ch.commands.includes('deploy')
      && !window.confirm(t.deployConfirm)) return
    setBusy(true)
    try {
      await api.put(`${BASE}/commands`, { channel_id: ch.id, commands: sel })
      onSaved(t.commandsSaved)
    } catch (e) {
      onError(String(e))
    } finally {
      setBusy(false)
    }
  }
  return (
    <div className="mt-2 ml-2 pl-3 border-l-2 border-[var(--border)]" data-testid={`cmds-${ch.id}`}>
      <div className="text-xs text-muted mb-1">{t.commandsHelp}</div>
      <div className="flex flex-wrap gap-x-4 gap-y-1">
        {catalog.map((c) => (
          <label key={c.id} className="inline-flex items-center gap-1 text-sm" title={c.example}>
            <input type="checkbox" checked={sel.includes(c.id)} disabled={busy} onChange={(e) => toggle(c.id, e.target.checked)} />
            {c.label}
          </label>
        ))}
      </div>
      {dirty && <div className="mt-2"><Btn primary disabled={busy} onClick={save}>{busy ? t.saving : t.saveCommands}</Btn></div>}
      {caps.programs && <ProgramsEditor ch={ch} onSaved={onSaved} onError={onError} />}
    </div>
  )
}

function ProgramsEditor({ ch, onSaved, onError }: { ch: PeopleChannel; onSaved: (msg: string) => void; onError: (m: string) => void }) {
  const api = useAppApi()
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const save = async (progs: string[]) => {
    setBusy(true)
    try {
      await api.put(`${BASE}/programs`, { channel_id: ch.id, programs: progs })
      onSaved(t.programsSaved)
    } catch (e) {
      onError(String(e))
    } finally {
      setBusy(false)
    }
  }
  return (
    <div className="mt-3">
      <div className="text-xs text-muted mb-1">{t.programsHelp}</div>
      <div className="flex flex-wrap gap-2 items-center">
        {ch.programs.map((p) => (
          <span key={p} className="inline-flex items-center gap-1">
            <Badge variant="aim">{p}</Badge>
            <button type="button" aria-label={t.removeProgram(p)} className="text-xs text-muted hover:text-danger" disabled={busy}
              onClick={() => { void save(ch.programs.filter((x) => x !== p)) }}>✕</button>
          </span>
        ))}
        <Input aria-label={t.addProgramLabel(ch.name || ch.id)} placeholder={t.programsPlaceholder} className="max-w-[220px]" value={name} onChange={(e) => setName(e.target.value)} />
        {name.trim() && <Btn primary disabled={busy} onClick={() => { const n = name.trim(); setName(''); void save([...ch.programs, n]) }}>{t.add}</Btn>}
      </div>
    </div>
  )
}

function MaintainersCard({ people, caps, onSaved, onError }: { people: People; caps: Caps; onSaved: (msg: string) => void; onError: (m: string) => void }) {
  // Channels that carry a maintainer or saved rules first; the rest keep the list order.
  const weight = (c: PeopleChannel) => (c.maintainers.length ? 0 : c.commands.length || c.programs.length ? 1 : 2)
  const rows = [...people.channels].sort((a, b) => weight(a) - weight(b))
  return (
    <Card>
      <CardTitle>{t.maintainersTitle}</CardTitle>
      <ul className="text-xs text-muted mb-2 list-disc pl-5 space-y-0.5">
        {(caps.confinement ? t.maintainersHelpConfined : t.maintainersHelp).map((x) => <li key={x}>{x}</li>)}
      </ul>
      <div className="text-sm">
        {rows.map((ch) => (
          <ChannelRoleRow key={`${ch.id}:${ch.maintainers.join(',')}:${ch.commands.join(',')}:${ch.programs.join(',')}`}
            ch={ch} members={people.members} catalog={people.command_catalog} caps={caps} onSaved={onSaved} onError={onError} />
        ))}
      </div>
      <p className="text-xs text-muted mt-2 font-mono">{people.roles_path}</p>
    </Card>
  )
}

function SettingsCard({ settings, onSaved, onError }: { settings: Settings; onSaved: () => void; onError: (m: string) => void }) {
  const api = useAppApi()
  const [s, setS] = useState<Settings>(settings)
  useEffect(() => setS(settings), [settings])
  const save = async () => {
    try {
      await api.put(`${BASE}/settings`, s)
      onSaved()
    } catch (e) {
      onError(String(e))
    }
  }
  return (
    <Card>
      <CardTitle>{t.settingsTitle}</CardTitle>
      <div className="grid gap-3 text-sm grid-cols-[180px_1fr] items-center">
        <label htmlFor="co-mode">{t.detectMode}</label>
        <Select label={t.detectMode} value={s.mode} options={['auto', 'notify', 'off']} onChange={(v) => setS({ ...s, mode: v as Settings['mode'] })} />
        <label htmlFor="co-root">{t.workspaceRoot}</label>
        <Input id="co-root" value={s.workspace_root} onChange={(e) => setS({ ...s, workspace_root: e.target.value })} />
        <span>{t.defaultActivation}</span>
        <Select label={t.defaultActivation} value={s.activation} options={ACTIVATIONS} onChange={(v) => setS({ ...s, activation: v })} />
        <span>{t.defaultFollow}</span>
        <Toggle checked={s.thread_follow} onChange={(v) => setS({ ...s, thread_follow: v })} label={t.defaultFollow} />
        <span>{t.ownerMember}</span>
        <Toggle checked={s.require_owner_member} onChange={(v) => setS({ ...s, require_owner_member: v })} label={t.ownerMember} />
        <span>{t.dedicatedMemory}</span>
        <Toggle checked={s.dedicated_memory} onChange={(v) => setS({ ...s, dedicated_memory: v })} label={t.dedicatedMemory} />
        <label htmlFor="co-poll">{t.pollSecs}</label>
        <Input id="co-poll" type="number" min={60} max={3600} value={s.poll_secs} onChange={(e) => setS({ ...s, poll_secs: Number(e.target.value) })} />
      </div>
      <div className="mt-3"><Btn primary onClick={save}>{t.saveSettings}</Btn></div>
      <p className="text-xs text-muted mt-2">
        {t.modeHelp}
      </p>
    </Card>
  )
}

export default function SlackChannelsOnboard() {
  const api = useAppApi()
  const [data, setData] = useState<ListResponse | null>(null)
  const [people, setPeople] = useState<People | null>(null)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')

  const load = useCallback(() => {
    setError('')
    api.get<ListResponse>(`${BASE}/channels`).then(setData).catch((e) => setError(String(e)))
    api.get<People>(`${BASE}/people`).then(setPeople).catch((e) => setError(String(e)))
    // eslint-disable-next-line react-hooks/exhaustive-deps -- api is the host's scoped client
  }, [])
  useEffect(() => { load() }, [load])
  const saved = (msg: string) => { setNotice(msg); load() }

  const configured = data?.channels.filter((c) => c.configured) ?? []
  const pending = data?.channels.filter((c) => !c.configured && c.bot_member && !c.id.startsWith('D')) ?? []
  const caps: Caps = people?.capabilities ?? NO_CAPS
  const openIds = new Set((people?.channels ?? []).filter((c) => c.open).map((c) => c.id))

  return (
    <>
      <PageHeader title="Slack Channels Onboard" subtitle={t.subtitle} actions={<Btn onClick={load}>{t.refresh}</Btn>} />
      <div className="px-6 pb-8 overflow-y-auto flex-1 min-h-0 space-y-4">
        {error && <Card><div role="alert" className="text-danger text-sm">{error}</div></Card>}
        {notice && <Card><div role="status" className="text-sm">{notice}</div></Card>}
        {data?.slack_error && <Card><div role="alert" className="text-warn text-sm">{t.slackError}{data.slack_error}</div></Card>}
        {people?.roles_error && <Card><div role="alert" className="text-danger text-sm">{t.rolesError}{people.roles_error}</div></Card>}
        <div className="grid gap-3.5 grid-cols-[repeat(auto-fit,minmax(150px,1fr))]">
          <StatCard label={t.statConfigured} value={data ? configured.length : null} accent />
          <StatCard label={t.statPending} value={data ? pending.length : null} />
          {caps.open_channel && <StatCard label={t.statOpen} value={people ? openIds.size : null} />}
          <StatCard label={t.statMode} value={data ? data.settings.mode : null} />
        </div>

        <Card>
          <CardTitle>{t.pendingTitle}</CardTitle>
          {data && pending.length === 0 ? (
            <EmptyState icon="✓" title={t.pendingEmptyTitle} subtitle={t.pendingEmptySub} />
          ) : (
            <table className="w-full text-left"><tbody>
              {pending.map((r) => data && <PendingRow key={r.id} row={r} settings={data.settings} onDone={load} onError={setError} />)}
            </tbody></table>
          )}
        </Card>

        <Card>
          <CardTitle>{t.configuredTitle}</CardTitle>
          {caps.open_channel && <p className="text-xs text-muted mb-2">{t.openHelp}</p>}
          <table className="w-full text-left text-sm">
            <thead><tr className="text-xs text-muted">
              <th className="pb-2 pr-3">{t.colChannel}</th><th className="pb-2 pr-3">{t.colAgent}</th>
              <th className="pb-2 pr-3">{t.colWorkspace}</th><th className="pb-2 pr-3">{t.colActivation}</th>
              <th className="pb-2 pr-3">{t.colFollow}</th>{caps.open_channel && <th className="pb-2 pr-3">{t.colOpen}</th>}<th className="pb-2" />
            </tr></thead>
            <tbody>
              {configured.map((r) => <ConfiguredRow key={`${r.id}:${r.workspace_dir}:${r.activation}:${r.thread_follow}:${openIds.has(r.id)}`} row={r} open={openIds.has(r.id)} canOpen={caps.open_channel} onSaved={load} onError={setError} />)}
            </tbody>
          </table>
        </Card>

        {people && !caps.any && (
          <Card>
            <CardTitle>{t.peopleUnsupportedTitle}</CardTitle>
            <p className="text-sm text-muted">{t.peopleUnsupported}</p>
          </Card>
        )}
        {people && caps.members && <MembersCard people={people} onSaved={saved} onError={setError} />}
        {people && caps.maintainers && <MaintainersCard people={people} caps={caps} onSaved={saved} onError={setError} />}

        {data && <SettingsCard settings={data.settings} onSaved={load} onError={setError} />}
      </div>
    </>
  )
}
