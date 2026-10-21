/**
 * UI strings. English is the default; Vietnamese is picked when the browser or
 * the dashboard document asks for it. Keys are shared, so a missing translation
 * falls back to English instead of rendering a key.
 */
const en = {
  subtitle: 'One agent, workspace and private memory per Slack channel',
  refresh: 'Refresh',
  saving: 'Saving…',
  creating: 'Creating…',
  save: 'Save',
  add: 'Add',
  remove: 'Remove',
  statConfigured: 'Configured',
  statPending: 'Waiting',
  statOpen: 'Open channels',
  statMode: 'Mode',
  slackError: 'Could not read the channel list from Slack: ',
  rolesError: 'The roles file is invalid, not overwriting it: ',
  pendingTitle: 'Waiting for onboarding',
  pendingEmptyTitle: 'No channel is waiting',
  pendingEmptySub: 'Add the bot to a new channel and it shows up here.',
  pendingPlan: (name: string, root: string, dedicated: boolean) =>
    `→ agent ${name}, workspace ${root}/${name}, ${dedicated ? 'private memory' : 'shared memory'}`,
  configuredTitle: 'Configured channels',
  openHelp:
    'Open: every member of the channel (not guests, not people from another workspace) may talk to the bot in that channel, read-only, even when they are not in the Members list.',
  colChannel: 'Channel',
  colAgent: 'Agent',
  colWorkspace: 'Workspace',
  colActivation: 'Activation',
  colFollow: 'thread_follow',
  colOpen: 'Open',
  colBackend: 'Agent backend',
  backendInherit: (d: string) => `Gateway default (${d})`,
  backendMissing: ' (not installed)',
  backendUnusable: ' (unusable)',
  backendAria: (a: string) => `Backend of agent ${a}`,
  backendConfirm: (a: string, name: string, maint: boolean) =>
    [
      `Switch agent ${a} to the ${name} backend?`,
      'Applies to new threads only; a running thread keeps its backend.',
      'Every channel bound to this agent switches with it.',
      ...(maint ? ['This channel has maintainers: their rules are tested most on Claude.'] : []),
    ].join('\n'),
  backendSaved: (a: string, name: string, others: number) =>
    `Agent ${a} → ${name}. Applies to new threads${others ? `; ${others} other channel(s) sharing this agent switched too` : ''}.`,
  backendHelp: (refuses: boolean): string =>
    refuses
      ? 'Agent backend: the harness the channel\'s agent runs on, for new threads. A backend that is not installed or is blocked makes the bot refuse and say why in the thread; it never falls back to Kiro CLI.'
      : 'Agent backend: the harness the channel\'s agent runs on, for new threads. On this gateway a backend that cannot run falls back to Kiro CLI.',
  botLeft: 'bot is no longer in the channel',
  unbind: 'Unbind',
  unbindConfirm: (c: string) => `Remove the configuration of #${c}? The bot has left this channel. Its agent, workspace and memory are kept.`,
  openConfirm: (c: string) =>
    `Open #${c} to EVERY member of the channel (not guests or people from another workspace)? They can only read files in this channel's workspace.`,
  openToggle: (c: string) => `Open #${c} to every channel member`,
  workspaceOf: (c: string) => `Workspace of #${c}`,
  defaultAgent: '(default agent)',
  // people
  peopleUnsupportedTitle: 'Members and maintainers',
  peopleUnsupported:
    'This Kiro Crew gateway only lets the owner use the bot on Slack, so members, maintainers, approved commands and open channels would have no effect and are disabled here. They need a gateway with per-user Slack access control (see the README, section "People").',
  membersTitle: 'Members',
  membersHelp: [
    'May talk to the bot in every channel it is in, read-only: they can read files in that channel\'s workspace (not .env, keys, .git/…), cannot edit files or run commands.',
    'No DMs, no clicking the bot\'s buttons, no spawn/cron/sending messages.',
    'People outside this list can still talk in a channel whose Open switch is on, with the same read-only rights.',
  ],
  ownerBadge: 'owner · full access',
  addMemberLabel: 'Slack user ID to add',
  addMemberPlaceholder: 'Slack user ID, e.g. U0XXXXXXXXX',
  addMember: 'Add member',
  memberIdHint: 'To get an ID: open the person\'s Slack profile → ⋮ → Copy member ID.',
  removeMemberConfirm: (n: string) => `Remove ${n} from the members? They also lose maintainer rights in every channel.`,
  savedLive: 'Saved, effective immediately.',
  savedNeedsRestart: 'Saved. The gateway did not hot-apply it; restart it to take effect.',
  maintainersTitle: 'Maintainers per channel',
  maintainersHelpConfined: [
    'A maintainer has full power INSIDE the channel\'s workspace: edit files, run any command, deploy. The agent process of that channel runs in an OS sandbox, so other workspaces and the owner\'s secrets do not exist for it.',
    'In other channels they are a plain member. They must be a member first.',
    'Whatever they need to deploy (scoped tokens, deploy keys) the owner puts into the workspace itself.',
  ],
  maintainersHelp: [
    'A maintainer can edit files in that channel\'s workspace (not .git/, .kiro/, .env*, keys, build config) and run the approved commands. In other channels they are a plain member. They must be a member first.',
    'A command they are not allowed yet: the bot asks the owner on Slack (Allow once / Allow this turn / Always allow / Deny). "Always allow" shows up here.',
    'Extra programs are still path-checked (inside the workspace, never a secret file). Shells, python/node, curl, npm… and package installs or remote databases can never be approved.',
  ],
  noWorkspace: '(no workspace yet)',
  noMaintainer: 'No maintainer',
  removeMaintainer: (n: string) => `Remove maintainer ${n}`,
  rulesSummary: (c: number, p: number, open: boolean) => `${c} commands · ${p} programs ${open ? '▴' : '▾'}`,
  addMaintainerLabel: (c: string) => `Add a maintainer to #${c}`,
  addMaintainer: 'Add maintainer…',
  noMoreMembers: 'No member left',
  maintainersSaved: 'Maintainers saved, effective immediately.',
  commandsHelp: 'Approved commands — a maintainer runs them without asking:',
  deployConfirm: 'Deploy runs against PRODUCTION with your cloud account. Let maintainers deploy on their own?',
  saveCommands: 'Save commands',
  commandsSaved: 'Approved commands saved, effective immediately.',
  programsHelp: 'Extra approved programs:',
  programsPlaceholder: 'e.g. sed, jq',
  addProgramLabel: (c: string) => `Add a program to #${c}`,
  removeProgram: (p: string) => `Remove program ${p}`,
  programsSaved: 'Approved programs saved.',
  // settings
  settingsTitle: 'Automatic onboarding',
  detectMode: 'Detection mode',
  workspaceRoot: 'Workspace root directory',
  defaultActivation: 'Default activation',
  defaultFollow: 'Default thread_follow',
  ownerMember: 'Only when the owner is in the channel',
  dedicatedMemory: 'Private memory per channel',
  pollSecs: 'Poll interval (seconds, 60–3600)',
  saveSettings: 'Save settings',
  modeHelp: 'auto: create the agent as soon as the bot joins a new channel, then DM you. notify: DM only. off: no background polling.',
}

type Strings = typeof en

const vi: Partial<Strings> = {
  subtitle: 'Mỗi Slack channel một agent, workspace và memory riêng',
  refresh: 'Làm mới',
  saving: 'Đang lưu…',
  creating: 'Đang tạo…',
  save: 'Lưu',
  add: 'Thêm',
  remove: 'Gỡ',
  statConfigured: 'Đã cấu hình',
  statPending: 'Chờ onboard',
  statOpen: 'Channel mở',
  statMode: 'Chế độ',
  slackError: 'Không đọc được danh sách channel từ Slack: ',
  rolesError: 'File vai trò lỗi, không ghi đè: ',
  pendingTitle: 'Chờ onboard',
  pendingEmptyTitle: 'Không có channel nào đang chờ',
  pendingEmptySub: 'Thêm bot vào một channel mới để nó xuất hiện ở đây.',
  pendingPlan: (name, root, dedicated) => `→ agent ${name}, workspace ${root}/${name}, ${dedicated ? 'memory riêng' : 'memory chung'}`,
  configuredTitle: 'Channel đã cấu hình',
  openHelp:
    'Mở: mọi thành viên của channel (không gồm guest và người ngoài workspace) chat được với bot ở channel đó, quyền chỉ đọc, kể cả khi không có trong danh sách Member.',
  colOpen: 'Mở',
  colBackend: 'Agent backend',
  backendInherit: (d) => `Mặc định gateway (${d})`,
  backendMissing: ' (chưa cài)',
  backendUnusable: ' (không dùng được)',
  backendAria: (a) => `Backend của agent ${a}`,
  backendConfirm: (a, name, maint) =>
    [
      `Chuyển agent ${a} sang backend ${name}?`,
      'Chỉ áp dụng cho thread mới; thread đang chạy giữ backend cũ.',
      'Mọi channel dùng chung agent này đều đổi theo.',
      ...(maint ? ['Channel này có maintainer: rule của maintainer mới được kiểm thử kỹ trên Claude.'] : []),
    ].join('\n'),
  backendSaved: (a, name, others) =>
    `Agent ${a} → ${name}. Áp dụng cho thread mới${others ? `; đổi luôn ${others} channel khác dùng chung agent này` : ''}.`,
  backendHelp: (refuses) =>
    refuses
      ? 'Agent backend: harness mà agent của channel chạy trên, áp dụng cho thread mới. Backend chưa cài hoặc bị chặn thì bot từ chối chạy và báo lý do trong thread, không tự chuyển sang Kiro CLI.'
      : 'Agent backend: harness mà agent của channel chạy trên, áp dụng cho thread mới. Trên gateway này, backend không chạy được sẽ tự chuyển sang Kiro CLI.',
  botLeft: 'bot không còn trong channel',
  unbind: 'Gỡ',
  unbindConfirm: (c) => `Gỡ cấu hình của #${c}? Bot đã rời channel này. Agent, workspace và memory được giữ nguyên.`,
  openConfirm: (c) =>
    `Mở #${c} cho MỌI thành viên của channel (không gồm guest và người ngoài workspace) chat với bot? Họ chỉ đọc được file trong workspace của channel này.`,
  openToggle: (c) => `Mở #${c} cho mọi thành viên channel`,
  workspaceOf: (c) => `Workspace của #${c}`,
  peopleUnsupportedTitle: 'Member và maintainer',
  peopleUnsupported:
    'Gateway Kiro Crew này chỉ cho owner dùng bot trên Slack, nên member, maintainer, lệnh được duyệt và channel mở sẽ không có tác dụng và bị tắt ở đây. Cần gateway có kiểm soát truy cập Slack theo từng người (xem README, mục "People").',
  membersTitle: 'Member',
  membersHelp: [
    'Chat được với bot ở mọi channel bot có mặt, nhưng chỉ đọc: đọc file trong workspace của channel đó (trừ .env, khoá, .git/…), không sửa file, không chạy lệnh.',
    'Không DM, không bấm nút của bot, không spawn/cron/gửi tin.',
    'Người ngoài danh sách vẫn chat được ở channel bật cột Mở, với cùng quyền chỉ đọc.',
  ],
  ownerBadge: 'owner · toàn quyền',
  addMemberLabel: 'Slack user ID cần thêm',
  addMemberPlaceholder: 'Slack user ID, ví dụ U0XXXXXXXXX',
  addMember: 'Thêm member',
  memberIdHint: 'Lấy ID: mở profile người đó trên Slack → ⋮ → Copy member ID.',
  removeMemberConfirm: (n) => `Gỡ ${n} khỏi danh sách member? Người này cũng mất quyền maintainer ở mọi channel.`,
  savedLive: 'Đã lưu, có hiệu lực ngay.',
  savedNeedsRestart: 'Đã lưu. Gateway chưa nhận nóng — cần restart để áp dụng.',
  maintainersTitle: 'Maintainer theo channel',
  maintainersHelpConfined: [
    'Maintainer toàn quyền TRONG workspace của channel: sửa file, chạy mọi lệnh, deploy. Process agent của channel đó chạy trong sandbox của hệ điều hành, nên workspace khác và bí mật của owner không tồn tại với nó.',
    'Ở channel khác họ chỉ là member. Phải là member trước.',
    'Thứ cần để deploy (token phạm vi hẹp, deploy key) owner đặt vào chính workspace đó.',
  ],
  maintainersHelp: [
    'Maintainer sửa được file trong workspace của channel đó (trừ .git/, .kiro/, .env*, khoá, file cấu hình build) và chạy các lệnh đã duyệt. Ở channel khác họ chỉ là member. Phải là member trước.',
    'Lệnh chưa có quyền: bot hỏi owner trên Slack (Cho phép 1 lần / Cho phép cả lượt này / Luôn cho phép / Từ chối). «Luôn cho phép» hiện ở đây.',
    'Chương trình duyệt thêm vẫn bị kiểm đường dẫn (trong workspace, không phải file bí mật). Shell, python/node, curl, npm… và npm install, DB remote không bao giờ duyệt được.',
  ],
  noWorkspace: '(chưa có workspace)',
  noMaintainer: 'Chưa có maintainer',
  removeMaintainer: (n) => `Gỡ maintainer ${n}`,
  rulesSummary: (c, p, open) => `${c} lệnh · ${p} chương trình ${open ? '▴' : '▾'}`,
  addMaintainerLabel: (c) => `Thêm maintainer cho #${c}`,
  addMaintainer: 'Thêm maintainer…',
  noMoreMembers: 'Không còn member',
  maintainersSaved: 'Đã lưu maintainer, có hiệu lực ngay.',
  commandsHelp: 'Lệnh được duyệt — maintainer chạy không cần hỏi:',
  deployConfirm: 'Deploy chạy lên PRODUCTION bằng tài khoản cloud của bạn. Cho phép maintainer tự deploy?',
  saveCommands: 'Lưu lệnh',
  commandsSaved: 'Đã lưu lệnh được duyệt, có hiệu lực ngay.',
  programsHelp: 'Chương trình được duyệt thêm:',
  programsPlaceholder: 'vd: sed, jq',
  addProgramLabel: (c) => `Thêm chương trình cho #${c}`,
  removeProgram: (p) => `Gỡ chương trình ${p}`,
  programsSaved: 'Đã lưu chương trình được duyệt.',
  settingsTitle: 'Cài đặt tự động',
  detectMode: 'Chế độ phát hiện',
  workspaceRoot: 'Thư mục gốc workspace',
  defaultActivation: 'Activation mặc định',
  defaultFollow: 'thread_follow mặc định',
  ownerMember: 'Chỉ khi owner ở trong channel',
  dedicatedMemory: 'Memory riêng cho mỗi channel',
  pollSecs: 'Chu kỳ quét (giây, 60–3600)',
  saveSettings: 'Lưu cài đặt',
  modeHelp: 'auto: tự tạo agent khi bot được thêm vào channel mới rồi DM cho bạn. notify: chỉ DM báo. off: tắt quét nền.',
}

function pickLang(): 'vi' | 'en' {
  const langs = [document.documentElement.lang, ...(navigator.languages || []), navigator.language]
  return langs.some((l) => (l || '').toLowerCase().startsWith('vi')) ? 'vi' : 'en'
}

export const t: Strings = pickLang() === 'vi' ? { ...en, ...vi } : en
