import { jsxs as c, Fragment as F, jsx as n } from "react/jsx-runtime";
import { useAppApi as S } from "@kirocrew/app-sdk";
import { PageHeader as G, Btn as _, Card as N, StatCard as I, CardTitle as $, EmptyState as j, Badge as H, Input as A, Toggle as M } from "@kirocrew/app-sdk/ui";
import { useState as f, useCallback as q, useEffect as B } from "react";
const E = {
  subtitle: "One agent, workspace and private memory per Slack channel",
  refresh: "Refresh",
  saving: "Saving…",
  creating: "Creating…",
  save: "Save",
  add: "Add",
  remove: "Remove",
  statConfigured: "Configured",
  statPending: "Waiting",
  statOpen: "Open channels",
  statMode: "Mode",
  slackError: "Could not read the channel list from Slack: ",
  rolesError: "The roles file is invalid, not overwriting it: ",
  pendingTitle: "Waiting for onboarding",
  pendingEmptyTitle: "No channel is waiting",
  pendingEmptySub: "Add the bot to a new channel and it shows up here.",
  pendingPlan: (e, t, d) => `→ agent ${e}, workspace ${t}/${e}, ${d ? "private memory" : "shared memory"}`,
  configuredTitle: "Configured channels",
  openHelp: "Open: every member of the channel (not guests, not people from another workspace) may talk to the bot in that channel, read-only, even when they are not in the Members list.",
  colChannel: "Channel",
  colAgent: "Agent",
  colWorkspace: "Workspace",
  colActivation: "Activation",
  colFollow: "thread_follow",
  colOpen: "Open",
  colBackend: "Agent backend",
  backendInherit: (e) => `Gateway default (${e})`,
  backendMissing: " (not installed)",
  backendUnusable: " (unusable)",
  backendAria: (e) => `Backend of agent ${e}`,
  backendConfirm: (e, t, d) => [
    `Switch agent ${e} to the ${t} backend?`,
    "Applies to new threads only; a running thread keeps its backend.",
    "Every channel bound to this agent switches with it.",
    ...d ? ["This channel has maintainers: their rules are tested most on Claude."] : []
  ].join(`
`),
  backendSaved: (e, t, d) => `Agent ${e} → ${t}. Applies to new threads${d ? `; ${d} other channel(s) sharing this agent switched too` : ""}.`,
  backendHelp: (e) => e ? "Agent backend: the harness the channel's agent runs on, for new threads. A backend that is not installed or is blocked makes the bot refuse and say why in the thread; it never falls back to Kiro CLI." : "Agent backend: the harness the channel's agent runs on, for new threads. On this gateway a backend that cannot run falls back to Kiro CLI.",
  botLeft: "bot is no longer in the channel",
  unbind: "Unbind",
  unbindConfirm: (e) => `Remove the configuration of #${e}? The bot has left this channel. Its agent, workspace and memory are kept.`,
  openConfirm: (e) => `Open #${e} to EVERY member of the channel (not guests or people from another workspace)? They can only read files in this channel's workspace.`,
  openToggle: (e) => `Open #${e} to every channel member`,
  workspaceOf: (e) => `Workspace of #${e}`,
  defaultAgent: "(default agent)",
  // people
  peopleUnsupportedTitle: "Members and maintainers",
  peopleUnsupported: "This Kiro Crew gateway only lets the owner use the bot on Slack, so members, maintainers, approved commands and open channels would have no effect and are disabled here. They need per-user Slack access control, which a stock gateway up to Kiro Crew 0.11.1 does not have. The optional gateway patches add it: run gateway-patches/apply.sh on the host that runs the gateway, then restart the gateway.",
  patchesLink: "Gateway patches: what each one adds and how to apply it",
  backendUnsupported: "Agent backend per channel is hidden: this gateway cannot pin a backend per agent. Kiro Crew 0.12.0 can; on 0.9.0 to 0.11.1, gateway patch Set U adds it.",
  membersTitle: "Members",
  membersHelp: [
    "May talk to the bot in every channel it is in, read-only: they can read files in that channel's workspace (not .env, keys, .git/…), cannot edit files or run commands.",
    "No DMs, no clicking the bot's buttons, no spawn/cron/sending messages.",
    "People outside this list can still talk in a channel whose Open switch is on, with the same read-only rights."
  ],
  ownerBadge: "owner · full access",
  addMemberLabel: "Slack user ID to add",
  addMemberPlaceholder: "Slack user ID, e.g. U0XXXXXXXXX",
  addMember: "Add member",
  memberIdHint: "To get an ID: open the person's Slack profile → ⋮ → Copy member ID.",
  removeMemberConfirm: (e) => `Remove ${e} from the members? They also lose maintainer rights in every channel.`,
  savedLive: "Saved, effective immediately.",
  savedNeedsRestart: "Saved. The gateway did not hot-apply it; restart it to take effect.",
  maintainersTitle: "Maintainers per channel",
  maintainersHelpConfined: [
    "A maintainer has full power INSIDE the channel's workspace: edit files, run any command, deploy. The agent process of that channel runs in an OS sandbox, so other workspaces and the owner's secrets do not exist for it.",
    "In other channels they are a plain member. They must be a member first.",
    "Whatever they need to deploy (scoped tokens, deploy keys) the owner puts into the workspace itself."
  ],
  maintainersHelp: [
    "A maintainer can edit files in that channel's workspace (not .git/, .kiro/, .env*, keys, build config) and run the approved commands. In other channels they are a plain member. They must be a member first.",
    'A command they are not allowed yet: the bot asks the owner on Slack (Allow once / Allow this turn / Always allow / Deny). "Always allow" shows up here.',
    "Extra programs are still path-checked (inside the workspace, never a secret file). Shells, python/node, curl, npm… and package installs or remote databases can never be approved."
  ],
  noWorkspace: "(no workspace yet)",
  noMaintainer: "No maintainer",
  removeMaintainer: (e) => `Remove maintainer ${e}`,
  rulesSummary: (e, t, d) => `${e} commands · ${t} programs ${d ? "▴" : "▾"}`,
  addMaintainerLabel: (e) => `Add a maintainer to #${e}`,
  addMaintainer: "Add maintainer…",
  noMoreMembers: "No member left",
  maintainersSaved: "Maintainers saved, effective immediately.",
  commandsHelp: "Approved commands — a maintainer runs them without asking:",
  deployConfirm: "Deploy runs against PRODUCTION with your cloud account. Let maintainers deploy on their own?",
  saveCommands: "Save commands",
  commandsSaved: "Approved commands saved, effective immediately.",
  programsHelp: "Extra approved programs:",
  programsPlaceholder: "e.g. sed, jq",
  addProgramLabel: (e) => `Add a program to #${e}`,
  removeProgram: (e) => `Remove program ${e}`,
  programsSaved: "Approved programs saved.",
  // settings
  settingsTitle: "Automatic onboarding",
  detectMode: "Detection mode",
  workspaceRoot: "Workspace root directory",
  defaultActivation: "Default activation",
  defaultFollow: "Default thread_follow",
  ownerMember: "Only when the owner is in the channel",
  dedicatedMemory: "Private memory per channel",
  repoWatch: "Watch the channel's GitHub repositories",
  repoWatchSecs: "Repository check interval (seconds)",
  pollSecs: "Poll interval (seconds, 60–3600)",
  saveSettings: "Save settings",
  modeHelp: "auto: create the agent as soon as the bot joins a new channel, then DM you. notify: DM only. off: no background polling."
}, V = {
  subtitle: "Mỗi Slack channel một agent, workspace và memory riêng",
  refresh: "Làm mới",
  saving: "Đang lưu…",
  creating: "Đang tạo…",
  save: "Lưu",
  add: "Thêm",
  remove: "Gỡ",
  statConfigured: "Đã cấu hình",
  statPending: "Chờ onboard",
  statOpen: "Channel mở",
  statMode: "Chế độ",
  slackError: "Không đọc được danh sách channel từ Slack: ",
  rolesError: "File vai trò lỗi, không ghi đè: ",
  pendingTitle: "Chờ onboard",
  pendingEmptyTitle: "Không có channel nào đang chờ",
  pendingEmptySub: "Thêm bot vào một channel mới để nó xuất hiện ở đây.",
  pendingPlan: (e, t, d) => `→ agent ${e}, workspace ${t}/${e}, ${d ? "memory riêng" : "memory chung"}`,
  configuredTitle: "Channel đã cấu hình",
  openHelp: "Mở: mọi thành viên của channel (không gồm guest và người ngoài workspace) chat được với bot ở channel đó, quyền chỉ đọc, kể cả khi không có trong danh sách Member.",
  colOpen: "Mở",
  colBackend: "Agent backend",
  backendInherit: (e) => `Mặc định gateway (${e})`,
  backendMissing: " (chưa cài)",
  backendUnusable: " (không dùng được)",
  backendAria: (e) => `Backend của agent ${e}`,
  backendConfirm: (e, t, d) => [
    `Chuyển agent ${e} sang backend ${t}?`,
    "Chỉ áp dụng cho thread mới; thread đang chạy giữ backend cũ.",
    "Mọi channel dùng chung agent này đều đổi theo.",
    ...d ? ["Channel này có maintainer: rule của maintainer mới được kiểm thử kỹ trên Claude."] : []
  ].join(`
`),
  backendSaved: (e, t, d) => `Agent ${e} → ${t}. Áp dụng cho thread mới${d ? `; đổi luôn ${d} channel khác dùng chung agent này` : ""}.`,
  backendHelp: (e) => e ? "Agent backend: harness mà agent của channel chạy trên, áp dụng cho thread mới. Backend chưa cài hoặc bị chặn thì bot từ chối chạy và báo lý do trong thread, không tự chuyển sang Kiro CLI." : "Agent backend: harness mà agent của channel chạy trên, áp dụng cho thread mới. Trên gateway này, backend không chạy được sẽ tự chuyển sang Kiro CLI.",
  botLeft: "bot không còn trong channel",
  unbind: "Gỡ",
  unbindConfirm: (e) => `Gỡ cấu hình của #${e}? Bot đã rời channel này. Agent, workspace và memory được giữ nguyên.`,
  openConfirm: (e) => `Mở #${e} cho MỌI thành viên của channel (không gồm guest và người ngoài workspace) chat với bot? Họ chỉ đọc được file trong workspace của channel này.`,
  openToggle: (e) => `Mở #${e} cho mọi thành viên channel`,
  workspaceOf: (e) => `Workspace của #${e}`,
  peopleUnsupportedTitle: "Member và maintainer",
  peopleUnsupported: "Gateway Kiro Crew này chỉ cho owner dùng bot trên Slack, nên member, maintainer, lệnh được duyệt và channel mở sẽ không có tác dụng và bị tắt ở đây. Cần kiểm soát truy cập Slack theo từng người, mà gateway gốc tới Kiro Crew 0.11.1 chưa có. Bộ patch gateway (tuỳ chọn) bổ sung việc này: chạy gateway-patches/apply.sh trên máy chạy gateway rồi restart gateway.",
  patchesLink: "Patch gateway: mỗi set thêm gì và cách áp dụng",
  backendUnsupported: "Cột Agent backend đang ẩn: gateway này chưa cho chọn backend theo từng agent. Kiro Crew 0.12.0 đã có; trên 0.9.0 tới 0.11.1, patch gateway Set U bổ sung việc này.",
  membersTitle: "Member",
  membersHelp: [
    "Chat được với bot ở mọi channel bot có mặt, nhưng chỉ đọc: đọc file trong workspace của channel đó (trừ .env, khoá, .git/…), không sửa file, không chạy lệnh.",
    "Không DM, không bấm nút của bot, không spawn/cron/gửi tin.",
    "Người ngoài danh sách vẫn chat được ở channel bật cột Mở, với cùng quyền chỉ đọc."
  ],
  ownerBadge: "owner · toàn quyền",
  addMemberLabel: "Slack user ID cần thêm",
  addMemberPlaceholder: "Slack user ID, ví dụ U0XXXXXXXXX",
  addMember: "Thêm member",
  memberIdHint: "Lấy ID: mở profile người đó trên Slack → ⋮ → Copy member ID.",
  removeMemberConfirm: (e) => `Gỡ ${e} khỏi danh sách member? Người này cũng mất quyền maintainer ở mọi channel.`,
  savedLive: "Đã lưu, có hiệu lực ngay.",
  savedNeedsRestart: "Đã lưu. Gateway chưa nhận nóng — cần restart để áp dụng.",
  maintainersTitle: "Maintainer theo channel",
  maintainersHelpConfined: [
    "Maintainer toàn quyền TRONG workspace của channel: sửa file, chạy mọi lệnh, deploy. Process agent của channel đó chạy trong sandbox của hệ điều hành, nên workspace khác và bí mật của owner không tồn tại với nó.",
    "Ở channel khác họ chỉ là member. Phải là member trước.",
    "Thứ cần để deploy (token phạm vi hẹp, deploy key) owner đặt vào chính workspace đó."
  ],
  maintainersHelp: [
    "Maintainer sửa được file trong workspace của channel đó (trừ .git/, .kiro/, .env*, khoá, file cấu hình build) và chạy các lệnh đã duyệt. Ở channel khác họ chỉ là member. Phải là member trước.",
    "Lệnh chưa có quyền: bot hỏi owner trên Slack (Cho phép 1 lần / Cho phép cả lượt này / Luôn cho phép / Từ chối). «Luôn cho phép» hiện ở đây.",
    "Chương trình duyệt thêm vẫn bị kiểm đường dẫn (trong workspace, không phải file bí mật). Shell, python/node, curl, npm… và npm install, DB remote không bao giờ duyệt được."
  ],
  noWorkspace: "(chưa có workspace)",
  noMaintainer: "Chưa có maintainer",
  removeMaintainer: (e) => `Gỡ maintainer ${e}`,
  rulesSummary: (e, t, d) => `${e} lệnh · ${t} chương trình ${d ? "▴" : "▾"}`,
  addMaintainerLabel: (e) => `Thêm maintainer cho #${e}`,
  addMaintainer: "Thêm maintainer…",
  noMoreMembers: "Không còn member",
  maintainersSaved: "Đã lưu maintainer, có hiệu lực ngay.",
  commandsHelp: "Lệnh được duyệt — maintainer chạy không cần hỏi:",
  deployConfirm: "Deploy chạy lên PRODUCTION bằng tài khoản cloud của bạn. Cho phép maintainer tự deploy?",
  saveCommands: "Lưu lệnh",
  commandsSaved: "Đã lưu lệnh được duyệt, có hiệu lực ngay.",
  programsHelp: "Chương trình được duyệt thêm:",
  programsPlaceholder: "vd: sed, jq",
  addProgramLabel: (e) => `Thêm chương trình cho #${e}`,
  removeProgram: (e) => `Gỡ chương trình ${e}`,
  programsSaved: "Đã lưu chương trình được duyệt.",
  settingsTitle: "Cài đặt tự động",
  detectMode: "Chế độ phát hiện",
  workspaceRoot: "Thư mục gốc workspace",
  defaultActivation: "Activation mặc định",
  defaultFollow: "thread_follow mặc định",
  ownerMember: "Chỉ khi owner ở trong channel",
  dedicatedMemory: "Memory riêng cho mỗi channel",
  repoWatch: "Theo dõi các repo GitHub của channel",
  repoWatchSecs: "Chu kỳ kiểm tra repo (giây)",
  pollSecs: "Chu kỳ quét (giây, 60–3600)",
  saveSettings: "Lưu cài đặt",
  modeHelp: "auto: tự tạo agent khi bot được thêm vào channel mới rồi DM cho bạn. notify: chỉ DM báo. off: tắt quét nền."
};
function z() {
  return [document.documentElement.lang, ...navigator.languages || [], navigator.language].some((t) => (t || "").toLowerCase().startsWith("vi")) ? "vi" : "en";
}
const a = z() === "vi" ? { ...E, ...V } : E, w = "/api/apps/slack-channels-onboard", R = "https://github.com/mvn-bachhuynh-dn/slack-channels-onboard/blob/main/gateway-patches/README.md", W = ["mention", "always", "observe", "review", "off"];
function D({ value: e, options: t, onChange: d, label: s }) {
  return /* @__PURE__ */ n(
    "select",
    {
      "aria-label": s,
      className: "bg-[var(--bg-input,transparent)] border border-[var(--border)] rounded px-2 py-1 text-sm",
      value: e,
      onChange: (i) => d(i.target.value),
      children: t.map((i) => /* @__PURE__ */ n("option", { value: i, children: i }, i))
    }
  );
}
const P = "__inherit__", O = (e) => e || "kiro";
function Y({ row: e, backends: t, hasMaintainers: d, onSaved: s, onError: i }) {
  const p = S(), [o, l] = f(!1), y = e.acp_backend ?? null, g = y === null || t.options.some((u) => u.id === y), v = a.backendInherit(O(t.default)), m = async (u) => {
    const h = u === P ? null : u, k = h === null ? v : O(h), x = e.agent || "";
    if (window.confirm(a.backendConfirm(x, k, d && h !== null && h !== "claude"))) {
      l(!0);
      try {
        const b = await p.put(`${w}/backend`, { channel_id: e.id, acp_backend: h });
        s(a.backendSaved(b.agent, k, b.channels.filter((r) => r !== e.id).length));
      } catch (b) {
        i(String(b));
      } finally {
        l(!1);
      }
    }
  };
  return /* @__PURE__ */ c(
    "select",
    {
      "aria-label": a.backendAria(e.agent || ""),
      className: "bg-[var(--bg-input,transparent)] border border-[var(--border)] rounded px-2 py-1 text-sm",
      value: y === null ? P : y,
      disabled: o || !e.agent,
      onChange: (u) => {
        m(u.target.value);
      },
      children: [
        /* @__PURE__ */ n("option", { value: P, children: v }),
        t.options.map((u) => /* @__PURE__ */ c("option", { value: u.id, disabled: u.installed === "missing", children: [
          u.label,
          u.installed === "missing" ? a.backendMissing : ""
        ] }, u.id || "kiro")),
        !g && y !== null && /* @__PURE__ */ c("option", { value: y, children: [
          O(y),
          a.backendUnusable
        ] })
      ]
    }
  );
}
function J({ row: e, open: t, canOpen: d, backends: s, hasMaintainers: i, onSaved: p, onNotice: o, onError: l }) {
  const y = S(), [g, v] = f(e.workspace_dir || ""), [m, u] = f(e.activation || "mention"), [h, k] = f(e.thread_follow ?? !0), [x, b] = f(!1), r = g !== (e.workspace_dir || "") || m !== e.activation || h !== e.thread_follow, T = async () => {
    b(!0);
    try {
      await y.post(`${w}/reconfigure`, {
        channel_id: e.id,
        workspace_dir: g !== (e.workspace_dir || "") ? g : void 0,
        activation: m !== e.activation ? m : void 0,
        thread_follow: h !== e.thread_follow ? h : void 0
      }), p();
    } catch (C) {
      l(String(C));
    } finally {
      b(!1);
    }
  }, U = async (C) => {
    if (!(C && !window.confirm(a.openConfirm(e.name || e.id)))) {
      b(!0);
      try {
        await y.put(`${w}/open`, { channel_id: e.id, open: C }), p();
      } catch (K) {
        l(String(K));
      } finally {
        b(!1);
      }
    }
  }, X = async () => {
    if (window.confirm(a.unbindConfirm(e.name || e.id))) {
      b(!0);
      try {
        await y.post(`${w}/unbind`, { channel_id: e.id }), p();
      } catch (C) {
        l(String(C));
      } finally {
        b(!1);
      }
    }
  };
  return /* @__PURE__ */ c("tr", { className: "border-t border-[var(--border)] align-top", "data-testid": `row-${e.id}`, children: [
    /* @__PURE__ */ c("td", { className: "py-2 pr-3", children: [
      /* @__PURE__ */ c("div", { className: "font-medium", children: [
        "#",
        e.name || e.id
      ] }),
      /* @__PURE__ */ n("div", { className: "text-xs text-muted", children: e.id }),
      !e.bot_member && /* @__PURE__ */ c("div", { className: "mt-1 flex items-center gap-2", children: [
        /* @__PURE__ */ n(H, { variant: "warn", children: a.botLeft }),
        /* @__PURE__ */ n(_, { danger: !0, disabled: x, onClick: X, children: a.unbind })
      ] })
    ] }),
    /* @__PURE__ */ c("td", { className: "py-2 pr-3", children: [
      /* @__PURE__ */ n("div", { className: "font-mono text-sm whitespace-nowrap", children: e.agent || a.defaultAgent }),
      /* @__PURE__ */ c("div", { className: "text-xs text-muted", children: [
        "memory: ",
        e.memory_store || "—"
      ] })
    ] }),
    (s == null ? void 0 : s.supported) && /* @__PURE__ */ n("td", { className: "py-2 pr-3", children: /* @__PURE__ */ n(Y, { row: e, backends: s, hasMaintainers: i, onSaved: o, onError: l }) }),
    /* @__PURE__ */ n("td", { className: "py-2 pr-3 w-[38%] min-w-[320px]", children: /* @__PURE__ */ n(A, { "aria-label": a.workspaceOf(e.name || e.id), title: g, className: "w-full font-mono text-xs", value: g, onChange: (C) => v(C.target.value), disabled: !e.agent }) }),
    /* @__PURE__ */ n("td", { className: "py-2 pr-3", children: /* @__PURE__ */ n(D, { label: "Activation", value: m, options: W, onChange: u }) }),
    /* @__PURE__ */ n("td", { className: "py-2 pr-3", children: /* @__PURE__ */ n(M, { checked: h, onChange: k, label: "thread_follow" }) }),
    d && /* @__PURE__ */ n("td", { className: "py-2 pr-3", children: /* @__PURE__ */ n(M, { checked: t, onChange: (C) => {
      U(C);
    }, label: a.openToggle(e.name || e.id) }) }),
    /* @__PURE__ */ n("td", { className: "py-2 w-[72px]", children: r && /* @__PURE__ */ n(_, { primary: !0, disabled: x, onClick: T, children: x ? a.saving : a.save }) })
  ] });
}
function Q({ row: e, settings: t, onDone: d, onError: s }) {
  const i = S(), [p, o] = f(!1), l = async () => {
    o(!0);
    try {
      await i.post(`${w}/onboard`, { channel_id: e.id, channel_name: e.name }), d();
    } catch (y) {
      s(String(y));
    } finally {
      o(!1);
    }
  };
  return /* @__PURE__ */ c("tr", { className: "border-t border-[var(--border)]", "data-testid": `pending-${e.id}`, children: [
    /* @__PURE__ */ c("td", { className: "py-2 pr-3", children: [
      /* @__PURE__ */ c("div", { className: "font-medium", children: [
        "#",
        e.name || e.id
      ] }),
      /* @__PURE__ */ n("div", { className: "text-xs text-muted", children: e.id })
    ] }),
    /* @__PURE__ */ n("td", { className: "py-2 pr-3 text-sm text-muted", children: /* @__PURE__ */ n("span", { className: "font-mono", children: a.pendingPlan(e.name || e.id, t.workspace_root, t.dedicated_memory) }) }),
    /* @__PURE__ */ n("td", { className: "py-2", children: /* @__PURE__ */ n(_, { primary: !0, disabled: p, onClick: l, children: p ? a.creating : "Onboard" }) })
  ] });
}
const Z = { members: !1, maintainers: !1, commands: !1, programs: !1, open_channel: !1, confinement: !1, any: !1 }, L = (e, t) => e && (e.display || e.name) || t;
function ee({ people: e, onSaved: t, onError: d }) {
  const s = S(), [i, p] = f(""), [o, l] = f(!1), y = async (m) => {
    l(!0);
    try {
      const u = await s.put(`${w}/members`, { members: m.map(({ slack_id: h, name: k }) => ({ slack_id: h, name: k })) });
      t(u.hot_applied ? a.savedLive : a.savedNeedsRestart);
    } catch (u) {
      d(String(u));
    } finally {
      l(!1);
    }
  }, g = async () => {
    const m = i.trim().toUpperCase();
    if (m) {
      l(!0);
      try {
        const u = await s.post(`${w}/resolve-user`, { slack_id: m });
        p(""), await y([...e.members, { slack_id: u.slack_id, name: u.name }]);
      } catch (u) {
        d(String(u)), l(!1);
      }
    }
  }, v = (m) => {
    const u = e.members.find((h) => h.slack_id === m);
    window.confirm(a.removeMemberConfirm(L(u, m))) && y(e.members.filter((h) => h.slack_id !== m));
  };
  return /* @__PURE__ */ c(N, { children: [
    /* @__PURE__ */ n($, { children: a.membersTitle }),
    /* @__PURE__ */ n("ul", { className: "text-xs text-muted mb-2 list-disc pl-5 space-y-0.5", children: a.membersHelp.map((m) => /* @__PURE__ */ n("li", { children: m }, m)) }),
    /* @__PURE__ */ n("table", { className: "w-full text-left text-sm", children: /* @__PURE__ */ c("tbody", { children: [
      /* @__PURE__ */ c("tr", { className: "border-t border-[var(--border)]", children: [
        /* @__PURE__ */ n("td", { className: "py-2 pr-3", children: e.owner.display || e.owner.slack_id }),
        /* @__PURE__ */ n("td", { className: "py-2 pr-3 font-mono text-xs text-muted", children: e.owner.slack_id }),
        /* @__PURE__ */ n("td", { className: "py-2", children: /* @__PURE__ */ n(H, { variant: "ok", children: a.ownerBadge }) })
      ] }),
      e.members.map((m) => /* @__PURE__ */ c("tr", { className: "border-t border-[var(--border)]", "data-testid": `member-${m.slack_id}`, children: [
        /* @__PURE__ */ n("td", { className: "py-2 pr-3", children: L(m, m.slack_id) }),
        /* @__PURE__ */ n("td", { className: "py-2 pr-3 font-mono text-xs text-muted", children: m.slack_id }),
        /* @__PURE__ */ n("td", { className: "py-2", children: /* @__PURE__ */ n(_, { disabled: o, onClick: () => v(m.slack_id), children: a.remove }) })
      ] }, m.slack_id))
    ] }) }),
    /* @__PURE__ */ c("div", { className: "mt-3 flex gap-2 items-center", children: [
      /* @__PURE__ */ n(A, { "aria-label": a.addMemberLabel, placeholder: a.addMemberPlaceholder, value: i, onChange: (m) => p(m.target.value) }),
      /* @__PURE__ */ n(_, { primary: !!i.trim(), disabled: o || !i.trim(), onClick: g, children: o ? a.saving : a.addMember })
    ] }),
    /* @__PURE__ */ n("p", { className: "text-xs text-muted mt-2", children: a.memberIdHint })
  ] });
}
function ne({ ch: e, members: t, catalog: d, caps: s, onSaved: i, onError: p }) {
  const o = S(), [l, y] = f(!1), [g, v] = f(""), [m, u] = f(!1), h = new Map(t.map((r) => [r.slack_id, r])), k = t.filter((r) => !e.maintainers.includes(r.slack_id)), x = e.commands.length > 0 || e.programs.length > 0, b = async (r) => {
    y(!0);
    try {
      await o.put(`${w}/maintainers`, { channel_id: e.id, maintainers: r }), i(a.maintainersSaved);
    } catch (T) {
      p(String(T));
    } finally {
      y(!1);
    }
  };
  return /* @__PURE__ */ c("div", { className: "border-t border-[var(--border)] py-2", "data-testid": `maint-${e.id}`, children: [
    /* @__PURE__ */ c("div", { className: "flex flex-wrap items-center gap-x-4 gap-y-2", children: [
      /* @__PURE__ */ c("div", { className: "min-w-[180px]", children: [
        /* @__PURE__ */ c("div", { className: "font-medium", children: [
          "#",
          e.name || e.id
        ] }),
        /* @__PURE__ */ n("div", { className: "text-xs text-muted font-mono truncate max-w-[260px]", title: e.workspace_dir, children: e.workspace_dir || a.noWorkspace })
      ] }),
      /* @__PURE__ */ c("div", { className: "flex flex-wrap gap-1 flex-1 min-w-[160px]", children: [
        e.maintainers.map((r) => /* @__PURE__ */ c("span", { className: "inline-flex items-center gap-1", children: [
          /* @__PURE__ */ n(H, { variant: "aim", children: L(h.get(r), r) }),
          /* @__PURE__ */ n(
            "button",
            {
              type: "button",
              "aria-label": a.removeMaintainer(L(h.get(r), r)),
              className: "text-xs text-muted hover:text-danger",
              disabled: l,
              onClick: () => b(e.maintainers.filter((T) => T !== r)),
              children: "✕"
            }
          )
        ] }, r)),
        e.maintainers.length === 0 && /* @__PURE__ */ n("span", { className: "text-xs text-muted", children: a.noMaintainer })
      ] }),
      s.commands && (e.maintainers.length > 0 || x) && /* @__PURE__ */ n(
        "button",
        {
          type: "button",
          className: "text-xs text-accent hover:underline",
          "aria-expanded": m,
          onClick: () => u((r) => !r),
          "data-testid": `maint-toggle-${e.id}`,
          children: a.rulesSummary(e.commands.length, e.programs.length, m)
        }
      ),
      /* @__PURE__ */ c("div", { className: "flex gap-2 items-center", children: [
        /* @__PURE__ */ c(
          "select",
          {
            "aria-label": a.addMaintainerLabel(e.name || e.id),
            className: "bg-[var(--bg-input,transparent)] border border-[var(--border)] rounded px-2 py-1 text-sm",
            value: g,
            onChange: (r) => v(r.target.value),
            disabled: l || k.length === 0 || !e.workspace_dir,
            children: [
              /* @__PURE__ */ n("option", { value: "", children: k.length ? a.addMaintainer : a.noMoreMembers }),
              k.map((r) => /* @__PURE__ */ n("option", { value: r.slack_id, children: L(r, r.slack_id) }, r.slack_id))
            ]
          }
        ),
        g && /* @__PURE__ */ n(_, { primary: !0, disabled: l, onClick: () => {
          b([...e.maintainers, g]), v("");
        }, children: a.add })
      ] })
    ] }),
    m && s.commands && /* @__PURE__ */ n(ae, { ch: e, catalog: d, caps: s, onSaved: i, onError: p })
  ] });
}
function ae({ ch: e, catalog: t, caps: d, onSaved: s, onError: i }) {
  const p = S(), [o, l] = f(e.commands), [y, g] = f(!1), v = o.slice().sort().join(",") !== e.commands.slice().sort().join(","), m = (h, k) => l((x) => k ? [...x.filter((b) => b !== h), h] : x.filter((b) => b !== h)), u = async () => {
    if (!(o.includes("deploy") && !e.commands.includes("deploy") && !window.confirm(a.deployConfirm))) {
      g(!0);
      try {
        await p.put(`${w}/commands`, { channel_id: e.id, commands: o }), s(a.commandsSaved);
      } catch (h) {
        i(String(h));
      } finally {
        g(!1);
      }
    }
  };
  return /* @__PURE__ */ c("div", { className: "mt-2 ml-2 pl-3 border-l-2 border-[var(--border)]", "data-testid": `cmds-${e.id}`, children: [
    /* @__PURE__ */ n("div", { className: "text-xs text-muted mb-1", children: a.commandsHelp }),
    /* @__PURE__ */ n("div", { className: "flex flex-wrap gap-x-4 gap-y-1", children: t.map((h) => /* @__PURE__ */ c("label", { className: "inline-flex items-center gap-1 text-sm", title: h.example, children: [
      /* @__PURE__ */ n("input", { type: "checkbox", checked: o.includes(h.id), disabled: y, onChange: (k) => m(h.id, k.target.checked) }),
      h.label
    ] }, h.id)) }),
    v && /* @__PURE__ */ n("div", { className: "mt-2", children: /* @__PURE__ */ n(_, { primary: !0, disabled: y, onClick: u, children: y ? a.saving : a.saveCommands }) }),
    d.programs && /* @__PURE__ */ n(te, { ch: e, onSaved: s, onError: i })
  ] });
}
function te({ ch: e, onSaved: t, onError: d }) {
  const s = S(), [i, p] = f(""), [o, l] = f(!1), y = async (g) => {
    l(!0);
    try {
      await s.put(`${w}/programs`, { channel_id: e.id, programs: g }), t(a.programsSaved);
    } catch (v) {
      d(String(v));
    } finally {
      l(!1);
    }
  };
  return /* @__PURE__ */ c("div", { className: "mt-3", children: [
    /* @__PURE__ */ n("div", { className: "text-xs text-muted mb-1", children: a.programsHelp }),
    /* @__PURE__ */ c("div", { className: "flex flex-wrap gap-2 items-center", children: [
      e.programs.map((g) => /* @__PURE__ */ c("span", { className: "inline-flex items-center gap-1", children: [
        /* @__PURE__ */ n(H, { variant: "aim", children: g }),
        /* @__PURE__ */ n(
          "button",
          {
            type: "button",
            "aria-label": a.removeProgram(g),
            className: "text-xs text-muted hover:text-danger",
            disabled: o,
            onClick: () => {
              y(e.programs.filter((v) => v !== g));
            },
            children: "✕"
          }
        )
      ] }, g)),
      /* @__PURE__ */ n(A, { "aria-label": a.addProgramLabel(e.name || e.id), placeholder: a.programsPlaceholder, className: "max-w-[220px]", value: i, onChange: (g) => p(g.target.value) }),
      i.trim() && /* @__PURE__ */ n(_, { primary: !0, disabled: o, onClick: () => {
        const g = i.trim();
        p(""), y([...e.programs, g]);
      }, children: a.add })
    ] })
  ] });
}
function re({ people: e, caps: t, onSaved: d, onError: s }) {
  const i = (o) => o.maintainers.length ? 0 : o.commands.length || o.programs.length ? 1 : 2, p = [...e.channels].sort((o, l) => i(o) - i(l));
  return /* @__PURE__ */ c(N, { children: [
    /* @__PURE__ */ n($, { children: a.maintainersTitle }),
    /* @__PURE__ */ n("ul", { className: "text-xs text-muted mb-2 list-disc pl-5 space-y-0.5", children: (t.confinement ? a.maintainersHelpConfined : a.maintainersHelp).map((o) => /* @__PURE__ */ n("li", { children: o }, o)) }),
    /* @__PURE__ */ n("div", { className: "text-sm", children: p.map((o) => /* @__PURE__ */ n(
      ne,
      {
        ch: o,
        members: e.members,
        catalog: e.command_catalog,
        caps: t,
        onSaved: d,
        onError: s
      },
      `${o.id}:${o.maintainers.join(",")}:${o.commands.join(",")}:${o.programs.join(",")}`
    )) }),
    /* @__PURE__ */ n("p", { className: "text-xs text-muted mt-2 font-mono", children: e.roles_path })
  ] });
}
function ie({ settings: e, onSaved: t, onError: d }) {
  const s = S(), [i, p] = f(e);
  B(() => p(e), [e]);
  const o = async () => {
    try {
      await s.put(`${w}/settings`, i), t();
    } catch (l) {
      d(String(l));
    }
  };
  return /* @__PURE__ */ c(N, { children: [
    /* @__PURE__ */ n($, { children: a.settingsTitle }),
    /* @__PURE__ */ c("div", { className: "grid gap-3 text-sm grid-cols-[180px_1fr] items-center", children: [
      /* @__PURE__ */ n("label", { htmlFor: "co-mode", children: a.detectMode }),
      /* @__PURE__ */ n(D, { label: a.detectMode, value: i.mode, options: ["auto", "notify", "off"], onChange: (l) => p({ ...i, mode: l }) }),
      /* @__PURE__ */ n("label", { htmlFor: "co-root", children: a.workspaceRoot }),
      /* @__PURE__ */ n(A, { id: "co-root", value: i.workspace_root, onChange: (l) => p({ ...i, workspace_root: l.target.value }) }),
      /* @__PURE__ */ n("span", { children: a.defaultActivation }),
      /* @__PURE__ */ n(D, { label: a.defaultActivation, value: i.activation, options: W, onChange: (l) => p({ ...i, activation: l }) }),
      /* @__PURE__ */ n("span", { children: a.defaultFollow }),
      /* @__PURE__ */ n(M, { checked: i.thread_follow, onChange: (l) => p({ ...i, thread_follow: l }), label: a.defaultFollow }),
      /* @__PURE__ */ n("span", { children: a.ownerMember }),
      /* @__PURE__ */ n(M, { checked: i.require_owner_member, onChange: (l) => p({ ...i, require_owner_member: l }), label: a.ownerMember }),
      /* @__PURE__ */ n("span", { children: a.dedicatedMemory }),
      /* @__PURE__ */ n(M, { checked: i.dedicated_memory, onChange: (l) => p({ ...i, dedicated_memory: l }), label: a.dedicatedMemory }),
      /* @__PURE__ */ n("span", { children: a.repoWatch }),
      /* @__PURE__ */ n(M, { checked: i.repo_watch, onChange: (l) => p({ ...i, repo_watch: l }), label: a.repoWatch }),
      /* @__PURE__ */ n("label", { htmlFor: "co-watch", children: a.repoWatchSecs }),
      /* @__PURE__ */ n(A, { id: "co-watch", type: "number", min: 600, max: 86400, value: i.repo_watch_secs, onChange: (l) => p({ ...i, repo_watch_secs: Number(l.target.value) }) }),
      /* @__PURE__ */ n("label", { htmlFor: "co-poll", children: a.pollSecs }),
      /* @__PURE__ */ n(A, { id: "co-poll", type: "number", min: 60, max: 3600, value: i.poll_secs, onChange: (l) => p({ ...i, poll_secs: Number(l.target.value) }) })
    ] }),
    /* @__PURE__ */ n("div", { className: "mt-3", children: /* @__PURE__ */ n(_, { primary: !0, onClick: o, children: a.saveSettings }) }),
    /* @__PURE__ */ n("p", { className: "text-xs text-muted mt-2", children: a.modeHelp })
  ] });
}
function de() {
  const e = S(), [t, d] = f(null), [s, i] = f(null), [p, o] = f(""), [l, y] = f(""), g = q(() => {
    o(""), e.get(`${w}/channels`).then(d).catch((r) => o(String(r))), e.get(`${w}/people`).then(i).catch((r) => o(String(r)));
  }, []);
  B(() => {
    g();
  }, [g]);
  const v = (r) => {
    y(r), g();
  }, m = (t == null ? void 0 : t.channels.filter((r) => r.configured)) ?? [], u = (t == null ? void 0 : t.channels.filter((r) => !r.configured && r.bot_member && !r.id.startsWith("D"))) ?? [], h = (s == null ? void 0 : s.capabilities) ?? Z, k = new Set(((s == null ? void 0 : s.channels) ?? []).filter((r) => r.open).map((r) => r.id)), x = new Set(((s == null ? void 0 : s.channels) ?? []).filter((r) => r.maintainers.length > 0).map((r) => r.id)), b = t == null ? void 0 : t.backends;
  return /* @__PURE__ */ c(F, { children: [
    /* @__PURE__ */ n(G, { title: "Slack Channels Onboard", subtitle: a.subtitle, actions: /* @__PURE__ */ n(_, { onClick: g, children: a.refresh }) }),
    /* @__PURE__ */ c("div", { className: "px-6 pb-8 overflow-y-auto flex-1 min-h-0 space-y-4", children: [
      p && /* @__PURE__ */ n(N, { children: /* @__PURE__ */ n("div", { role: "alert", className: "text-danger text-sm", children: p }) }),
      l && /* @__PURE__ */ n(N, { children: /* @__PURE__ */ n("div", { role: "status", className: "text-sm", children: l }) }),
      (t == null ? void 0 : t.slack_error) && /* @__PURE__ */ n(N, { children: /* @__PURE__ */ c("div", { role: "alert", className: "text-warn text-sm", children: [
        a.slackError,
        t.slack_error
      ] }) }),
      (s == null ? void 0 : s.roles_error) && /* @__PURE__ */ n(N, { children: /* @__PURE__ */ c("div", { role: "alert", className: "text-danger text-sm", children: [
        a.rolesError,
        s.roles_error
      ] }) }),
      /* @__PURE__ */ c("div", { className: "grid gap-3.5 grid-cols-[repeat(auto-fit,minmax(150px,1fr))]", children: [
        /* @__PURE__ */ n(I, { label: a.statConfigured, value: t ? m.length : null, accent: !0 }),
        /* @__PURE__ */ n(I, { label: a.statPending, value: t ? u.length : null }),
        h.open_channel && /* @__PURE__ */ n(I, { label: a.statOpen, value: s ? k.size : null }),
        /* @__PURE__ */ n(I, { label: a.statMode, value: t ? t.settings.mode : null })
      ] }),
      /* @__PURE__ */ c(N, { children: [
        /* @__PURE__ */ n($, { children: a.pendingTitle }),
        t && u.length === 0 ? /* @__PURE__ */ n(j, { icon: "✓", title: a.pendingEmptyTitle, subtitle: a.pendingEmptySub }) : /* @__PURE__ */ n("table", { className: "w-full text-left", children: /* @__PURE__ */ n("tbody", { children: u.map((r) => t && /* @__PURE__ */ n(Q, { row: r, settings: t.settings, onDone: g, onError: o }, r.id)) }) })
      ] }),
      /* @__PURE__ */ c(N, { children: [
        /* @__PURE__ */ n($, { children: a.configuredTitle }),
        h.open_channel && /* @__PURE__ */ n("p", { className: "text-xs text-muted mb-2", children: a.openHelp }),
        (b == null ? void 0 : b.supported) && /* @__PURE__ */ n("p", { className: "text-xs text-muted mb-2", children: a.backendHelp(b.refuses) }),
        b && !b.supported && /* @__PURE__ */ c("p", { className: "text-xs text-muted mb-2", children: [
          a.backendUnsupported,
          " ",
          /* @__PURE__ */ n("a", { href: R, target: "_blank", rel: "noreferrer", className: "underline", children: a.patchesLink })
        ] }),
        /* @__PURE__ */ c("table", { className: "w-full text-left text-sm", children: [
          /* @__PURE__ */ n("thead", { children: /* @__PURE__ */ c("tr", { className: "text-xs text-muted", children: [
            /* @__PURE__ */ n("th", { className: "pb-2 pr-3", children: a.colChannel }),
            /* @__PURE__ */ n("th", { className: "pb-2 pr-3", children: a.colAgent }),
            (b == null ? void 0 : b.supported) && /* @__PURE__ */ n("th", { className: "pb-2 pr-3", children: a.colBackend }),
            /* @__PURE__ */ n("th", { className: "pb-2 pr-3", children: a.colWorkspace }),
            /* @__PURE__ */ n("th", { className: "pb-2 pr-3", children: a.colActivation }),
            /* @__PURE__ */ n("th", { className: "pb-2 pr-3", children: a.colFollow }),
            h.open_channel && /* @__PURE__ */ n("th", { className: "pb-2 pr-3", children: a.colOpen }),
            /* @__PURE__ */ n("th", { className: "pb-2" })
          ] }) }),
          /* @__PURE__ */ n("tbody", { children: m.map((r) => /* @__PURE__ */ n(
            J,
            {
              row: r,
              open: k.has(r.id),
              canOpen: h.open_channel,
              backends: b,
              hasMaintainers: x.has(r.id),
              onSaved: g,
              onNotice: v,
              onError: o
            },
            `${r.id}:${r.workspace_dir}:${r.activation}:${r.thread_follow}:${k.has(r.id)}:${r.acp_backend ?? P}`
          )) })
        ] })
      ] }),
      s && !h.any && /* @__PURE__ */ c(N, { children: [
        /* @__PURE__ */ n($, { children: a.peopleUnsupportedTitle }),
        /* @__PURE__ */ n("p", { className: "text-sm text-muted", children: a.peopleUnsupported }),
        /* @__PURE__ */ n("p", { className: "text-sm mt-2", children: /* @__PURE__ */ n("a", { href: R, target: "_blank", rel: "noreferrer", className: "underline", children: a.patchesLink }) })
      ] }),
      s && h.members && /* @__PURE__ */ n(ee, { people: s, onSaved: v, onError: o }),
      s && h.maintainers && /* @__PURE__ */ n(re, { people: s, caps: h, onSaved: v, onError: o }),
      t && /* @__PURE__ */ n(ie, { settings: t.settings, onSaved: g, onError: o })
    ] })
  ] });
}
export {
  de as default
};
