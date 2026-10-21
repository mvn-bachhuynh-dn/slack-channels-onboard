import { jsxs as o, Fragment as R, jsx as n } from "react/jsx-runtime";
import { useAppApi as _ } from "@kirocrew/app-sdk";
import { PageHeader as X, Btn as C, Card as N, StatCard as P, CardTitle as S, EmptyState as B, Badge as D, Input as A, Toggle as $ } from "@kirocrew/app-sdk/ui";
import { useState as f, useCallback as W, useEffect as L } from "react";
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
  pendingPlan: (e, t, g) => `→ agent ${e}, workspace ${t}/${e}, ${g ? "private memory" : "shared memory"}`,
  configuredTitle: "Configured channels",
  openHelp: "Open: every member of the channel (not guests, not people from another workspace) may talk to the bot in that channel, read-only, even when they are not in the Members list.",
  colChannel: "Channel",
  colAgent: "Agent",
  colWorkspace: "Workspace",
  colActivation: "Activation",
  colFollow: "thread_follow",
  colOpen: "Open",
  botLeft: "bot is no longer in the channel",
  unbind: "Unbind",
  unbindConfirm: (e) => `Remove the configuration of #${e}? The bot has left this channel. Its agent, workspace and memory are kept.`,
  openConfirm: (e) => `Open #${e} to EVERY member of the channel (not guests or people from another workspace)? They can only read files in this channel's workspace.`,
  openToggle: (e) => `Open #${e} to every channel member`,
  workspaceOf: (e) => `Workspace of #${e}`,
  defaultAgent: "(default agent)",
  // people
  peopleUnsupportedTitle: "Members and maintainers",
  peopleUnsupported: 'This Kiro Crew gateway only lets the owner use the bot on Slack, so members, maintainers, approved commands and open channels would have no effect and are disabled here. They need a gateway with per-user Slack access control (see the README, section "People").',
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
  rulesSummary: (e, t, g) => `${e} commands · ${t} programs ${g ? "▴" : "▾"}`,
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
  pollSecs: "Poll interval (seconds, 60–3600)",
  saveSettings: "Save settings",
  modeHelp: "auto: create the agent as soon as the bot joins a new channel, then DM you. notify: DM only. off: no background polling."
}, q = {
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
  pendingPlan: (e, t, g) => `→ agent ${e}, workspace ${t}/${e}, ${g ? "memory riêng" : "memory chung"}`,
  configuredTitle: "Channel đã cấu hình",
  openHelp: "Mở: mọi thành viên của channel (không gồm guest và người ngoài workspace) chat được với bot ở channel đó, quyền chỉ đọc, kể cả khi không có trong danh sách Member.",
  colOpen: "Mở",
  botLeft: "bot không còn trong channel",
  unbind: "Gỡ",
  unbindConfirm: (e) => `Gỡ cấu hình của #${e}? Bot đã rời channel này. Agent, workspace và memory được giữ nguyên.`,
  openConfirm: (e) => `Mở #${e} cho MỌI thành viên của channel (không gồm guest và người ngoài workspace) chat với bot? Họ chỉ đọc được file trong workspace của channel này.`,
  openToggle: (e) => `Mở #${e} cho mọi thành viên channel`,
  workspaceOf: (e) => `Workspace của #${e}`,
  peopleUnsupportedTitle: "Member và maintainer",
  peopleUnsupported: 'Gateway Kiro Crew này chỉ cho owner dùng bot trên Slack, nên member, maintainer, lệnh được duyệt và channel mở sẽ không có tác dụng và bị tắt ở đây. Cần gateway có kiểm soát truy cập Slack theo từng người (xem README, mục "People").',
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
  rulesSummary: (e, t, g) => `${e} lệnh · ${t} chương trình ${g ? "▴" : "▾"}`,
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
  pollSecs: "Chu kỳ quét (giây, 60–3600)",
  saveSettings: "Lưu cài đặt",
  modeHelp: "auto: tự tạo agent khi bot được thêm vào channel mới rồi DM cho bạn. notify: chỉ DM báo. off: tắt quét nền."
};
function F() {
  return [document.documentElement.lang, ...navigator.languages || [], navigator.language].some((t) => (t || "").toLowerCase().startsWith("vi")) ? "vi" : "en";
}
const a = F() === "vi" ? { ...E, ...q } : E, x = "/api/apps/slack-channels-onboard", H = ["mention", "always", "observe", "review", "off"];
function O({ value: e, options: t, onChange: g, label: l }) {
  return /* @__PURE__ */ n(
    "select",
    {
      "aria-label": l,
      className: "bg-[var(--bg-input,transparent)] border border-[var(--border)] rounded px-2 py-1 text-sm",
      value: e,
      onChange: (i) => g(i.target.value),
      children: t.map((i) => /* @__PURE__ */ n("option", { value: i, children: i }, i))
    }
  );
}
function U({ row: e, open: t, canOpen: g, onSaved: l, onError: i }) {
  const m = _(), [r, s] = f(e.workspace_dir || ""), [v, p] = f(e.activation || "mention"), [y, h] = f(e.thread_follow ?? !0), [b, c] = f(!1), k = r !== (e.workspace_dir || "") || v !== e.activation || y !== e.thread_follow, d = async () => {
    c(!0);
    try {
      await m.post(`${x}/reconfigure`, {
        channel_id: e.id,
        workspace_dir: r !== (e.workspace_dir || "") ? r : void 0,
        activation: v !== e.activation ? v : void 0,
        thread_follow: y !== e.thread_follow ? y : void 0
      }), l();
    } catch (w) {
      i(String(w));
    } finally {
      c(!1);
    }
  }, M = async (w) => {
    if (!(w && !window.confirm(a.openConfirm(e.name || e.id)))) {
      c(!0);
      try {
        await m.put(`${x}/open`, { channel_id: e.id, open: w }), l();
      } catch (I) {
        i(String(I));
      } finally {
        c(!1);
      }
    }
  }, u = async () => {
    if (window.confirm(a.unbindConfirm(e.name || e.id))) {
      c(!0);
      try {
        await m.post(`${x}/unbind`, { channel_id: e.id }), l();
      } catch (w) {
        i(String(w));
      } finally {
        c(!1);
      }
    }
  };
  return /* @__PURE__ */ o("tr", { className: "border-t border-[var(--border)] align-top", "data-testid": `row-${e.id}`, children: [
    /* @__PURE__ */ o("td", { className: "py-2 pr-3", children: [
      /* @__PURE__ */ o("div", { className: "font-medium", children: [
        "#",
        e.name || e.id
      ] }),
      /* @__PURE__ */ n("div", { className: "text-xs text-muted", children: e.id }),
      !e.bot_member && /* @__PURE__ */ o("div", { className: "mt-1 flex items-center gap-2", children: [
        /* @__PURE__ */ n(D, { variant: "warn", children: a.botLeft }),
        /* @__PURE__ */ n(C, { danger: !0, disabled: b, onClick: u, children: a.unbind })
      ] })
    ] }),
    /* @__PURE__ */ o("td", { className: "py-2 pr-3", children: [
      /* @__PURE__ */ n("div", { className: "font-mono text-sm whitespace-nowrap", children: e.agent || a.defaultAgent }),
      /* @__PURE__ */ o("div", { className: "text-xs text-muted", children: [
        "memory: ",
        e.memory_store || "—"
      ] })
    ] }),
    /* @__PURE__ */ n("td", { className: "py-2 pr-3 w-[38%] min-w-[320px]", children: /* @__PURE__ */ n(A, { "aria-label": a.workspaceOf(e.name || e.id), title: r, className: "w-full font-mono text-xs", value: r, onChange: (w) => s(w.target.value), disabled: !e.agent }) }),
    /* @__PURE__ */ n("td", { className: "py-2 pr-3", children: /* @__PURE__ */ n(O, { label: "Activation", value: v, options: H, onChange: p }) }),
    /* @__PURE__ */ n("td", { className: "py-2 pr-3", children: /* @__PURE__ */ n($, { checked: y, onChange: h, label: "thread_follow" }) }),
    g && /* @__PURE__ */ n("td", { className: "py-2 pr-3", children: /* @__PURE__ */ n($, { checked: t, onChange: (w) => {
      M(w);
    }, label: a.openToggle(e.name || e.id) }) }),
    /* @__PURE__ */ n("td", { className: "py-2 w-[72px]", children: k && /* @__PURE__ */ n(C, { primary: !0, disabled: b, onClick: d, children: b ? a.saving : a.save }) })
  ] });
}
function j({ row: e, settings: t, onDone: g, onError: l }) {
  const i = _(), [m, r] = f(!1), s = async () => {
    r(!0);
    try {
      await i.post(`${x}/onboard`, { channel_id: e.id, channel_name: e.name }), g();
    } catch (v) {
      l(String(v));
    } finally {
      r(!1);
    }
  };
  return /* @__PURE__ */ o("tr", { className: "border-t border-[var(--border)]", "data-testid": `pending-${e.id}`, children: [
    /* @__PURE__ */ o("td", { className: "py-2 pr-3", children: [
      /* @__PURE__ */ o("div", { className: "font-medium", children: [
        "#",
        e.name || e.id
      ] }),
      /* @__PURE__ */ n("div", { className: "text-xs text-muted", children: e.id })
    ] }),
    /* @__PURE__ */ n("td", { className: "py-2 pr-3 text-sm text-muted", children: /* @__PURE__ */ n("span", { className: "font-mono", children: a.pendingPlan(e.name || e.id, t.workspace_root, t.dedicated_memory) }) }),
    /* @__PURE__ */ n("td", { className: "py-2", children: /* @__PURE__ */ n(C, { primary: !0, disabled: m, onClick: s, children: m ? a.creating : "Onboard" }) })
  ] });
}
const G = { members: !1, maintainers: !1, commands: !1, programs: !1, open_channel: !1, confinement: !1, any: !1 }, T = (e, t) => e && (e.display || e.name) || t;
function K({ people: e, onSaved: t, onError: g }) {
  const l = _(), [i, m] = f(""), [r, s] = f(!1), v = async (h) => {
    s(!0);
    try {
      const b = await l.put(`${x}/members`, { members: h.map(({ slack_id: c, name: k }) => ({ slack_id: c, name: k })) });
      t(b.hot_applied ? a.savedLive : a.savedNeedsRestart);
    } catch (b) {
      g(String(b));
    } finally {
      s(!1);
    }
  }, p = async () => {
    const h = i.trim().toUpperCase();
    if (h) {
      s(!0);
      try {
        const b = await l.post(`${x}/resolve-user`, { slack_id: h });
        m(""), await v([...e.members, { slack_id: b.slack_id, name: b.name }]);
      } catch (b) {
        g(String(b)), s(!1);
      }
    }
  }, y = (h) => {
    const b = e.members.find((c) => c.slack_id === h);
    window.confirm(a.removeMemberConfirm(T(b, h))) && v(e.members.filter((c) => c.slack_id !== h));
  };
  return /* @__PURE__ */ o(N, { children: [
    /* @__PURE__ */ n(S, { children: a.membersTitle }),
    /* @__PURE__ */ n("ul", { className: "text-xs text-muted mb-2 list-disc pl-5 space-y-0.5", children: a.membersHelp.map((h) => /* @__PURE__ */ n("li", { children: h }, h)) }),
    /* @__PURE__ */ n("table", { className: "w-full text-left text-sm", children: /* @__PURE__ */ o("tbody", { children: [
      /* @__PURE__ */ o("tr", { className: "border-t border-[var(--border)]", children: [
        /* @__PURE__ */ n("td", { className: "py-2 pr-3", children: e.owner.display || e.owner.slack_id }),
        /* @__PURE__ */ n("td", { className: "py-2 pr-3 font-mono text-xs text-muted", children: e.owner.slack_id }),
        /* @__PURE__ */ n("td", { className: "py-2", children: /* @__PURE__ */ n(D, { variant: "ok", children: a.ownerBadge }) })
      ] }),
      e.members.map((h) => /* @__PURE__ */ o("tr", { className: "border-t border-[var(--border)]", "data-testid": `member-${h.slack_id}`, children: [
        /* @__PURE__ */ n("td", { className: "py-2 pr-3", children: T(h, h.slack_id) }),
        /* @__PURE__ */ n("td", { className: "py-2 pr-3 font-mono text-xs text-muted", children: h.slack_id }),
        /* @__PURE__ */ n("td", { className: "py-2", children: /* @__PURE__ */ n(C, { disabled: r, onClick: () => y(h.slack_id), children: a.remove }) })
      ] }, h.slack_id))
    ] }) }),
    /* @__PURE__ */ o("div", { className: "mt-3 flex gap-2 items-center", children: [
      /* @__PURE__ */ n(A, { "aria-label": a.addMemberLabel, placeholder: a.addMemberPlaceholder, value: i, onChange: (h) => m(h.target.value) }),
      /* @__PURE__ */ n(C, { primary: !!i.trim(), disabled: r || !i.trim(), onClick: p, children: r ? a.saving : a.addMember })
    ] }),
    /* @__PURE__ */ n("p", { className: "text-xs text-muted mt-2", children: a.memberIdHint })
  ] });
}
function V({ ch: e, members: t, catalog: g, caps: l, onSaved: i, onError: m }) {
  const r = _(), [s, v] = f(!1), [p, y] = f(""), [h, b] = f(!1), c = new Map(t.map((u) => [u.slack_id, u])), k = t.filter((u) => !e.maintainers.includes(u.slack_id)), d = e.commands.length > 0 || e.programs.length > 0, M = async (u) => {
    v(!0);
    try {
      await r.put(`${x}/maintainers`, { channel_id: e.id, maintainers: u }), i(a.maintainersSaved);
    } catch (w) {
      m(String(w));
    } finally {
      v(!1);
    }
  };
  return /* @__PURE__ */ o("div", { className: "border-t border-[var(--border)] py-2", "data-testid": `maint-${e.id}`, children: [
    /* @__PURE__ */ o("div", { className: "flex flex-wrap items-center gap-x-4 gap-y-2", children: [
      /* @__PURE__ */ o("div", { className: "min-w-[180px]", children: [
        /* @__PURE__ */ o("div", { className: "font-medium", children: [
          "#",
          e.name || e.id
        ] }),
        /* @__PURE__ */ n("div", { className: "text-xs text-muted font-mono truncate max-w-[260px]", title: e.workspace_dir, children: e.workspace_dir || a.noWorkspace })
      ] }),
      /* @__PURE__ */ o("div", { className: "flex flex-wrap gap-1 flex-1 min-w-[160px]", children: [
        e.maintainers.map((u) => /* @__PURE__ */ o("span", { className: "inline-flex items-center gap-1", children: [
          /* @__PURE__ */ n(D, { variant: "aim", children: T(c.get(u), u) }),
          /* @__PURE__ */ n(
            "button",
            {
              type: "button",
              "aria-label": a.removeMaintainer(T(c.get(u), u)),
              className: "text-xs text-muted hover:text-danger",
              disabled: s,
              onClick: () => M(e.maintainers.filter((w) => w !== u)),
              children: "✕"
            }
          )
        ] }, u)),
        e.maintainers.length === 0 && /* @__PURE__ */ n("span", { className: "text-xs text-muted", children: a.noMaintainer })
      ] }),
      l.commands && (e.maintainers.length > 0 || d) && /* @__PURE__ */ n(
        "button",
        {
          type: "button",
          className: "text-xs text-accent hover:underline",
          "aria-expanded": h,
          onClick: () => b((u) => !u),
          "data-testid": `maint-toggle-${e.id}`,
          children: a.rulesSummary(e.commands.length, e.programs.length, h)
        }
      ),
      /* @__PURE__ */ o("div", { className: "flex gap-2 items-center", children: [
        /* @__PURE__ */ o(
          "select",
          {
            "aria-label": a.addMaintainerLabel(e.name || e.id),
            className: "bg-[var(--bg-input,transparent)] border border-[var(--border)] rounded px-2 py-1 text-sm",
            value: p,
            onChange: (u) => y(u.target.value),
            disabled: s || k.length === 0 || !e.workspace_dir,
            children: [
              /* @__PURE__ */ n("option", { value: "", children: k.length ? a.addMaintainer : a.noMoreMembers }),
              k.map((u) => /* @__PURE__ */ n("option", { value: u.slack_id, children: T(u, u.slack_id) }, u.slack_id))
            ]
          }
        ),
        p && /* @__PURE__ */ n(C, { primary: !0, disabled: s, onClick: () => {
          M([...e.maintainers, p]), y("");
        }, children: a.add })
      ] })
    ] }),
    h && l.commands && /* @__PURE__ */ n(z, { ch: e, catalog: g, caps: l, onSaved: i, onError: m })
  ] });
}
function z({ ch: e, catalog: t, caps: g, onSaved: l, onError: i }) {
  const m = _(), [r, s] = f(e.commands), [v, p] = f(!1), y = r.slice().sort().join(",") !== e.commands.slice().sort().join(","), h = (c, k) => s((d) => k ? [...d.filter((M) => M !== c), c] : d.filter((M) => M !== c)), b = async () => {
    if (!(r.includes("deploy") && !e.commands.includes("deploy") && !window.confirm(a.deployConfirm))) {
      p(!0);
      try {
        await m.put(`${x}/commands`, { channel_id: e.id, commands: r }), l(a.commandsSaved);
      } catch (c) {
        i(String(c));
      } finally {
        p(!1);
      }
    }
  };
  return /* @__PURE__ */ o("div", { className: "mt-2 ml-2 pl-3 border-l-2 border-[var(--border)]", "data-testid": `cmds-${e.id}`, children: [
    /* @__PURE__ */ n("div", { className: "text-xs text-muted mb-1", children: a.commandsHelp }),
    /* @__PURE__ */ n("div", { className: "flex flex-wrap gap-x-4 gap-y-1", children: t.map((c) => /* @__PURE__ */ o("label", { className: "inline-flex items-center gap-1 text-sm", title: c.example, children: [
      /* @__PURE__ */ n("input", { type: "checkbox", checked: r.includes(c.id), disabled: v, onChange: (k) => h(c.id, k.target.checked) }),
      c.label
    ] }, c.id)) }),
    y && /* @__PURE__ */ n("div", { className: "mt-2", children: /* @__PURE__ */ n(C, { primary: !0, disabled: v, onClick: b, children: v ? a.saving : a.saveCommands }) }),
    g.programs && /* @__PURE__ */ n(Y, { ch: e, onSaved: l, onError: i })
  ] });
}
function Y({ ch: e, onSaved: t, onError: g }) {
  const l = _(), [i, m] = f(""), [r, s] = f(!1), v = async (p) => {
    s(!0);
    try {
      await l.put(`${x}/programs`, { channel_id: e.id, programs: p }), t(a.programsSaved);
    } catch (y) {
      g(String(y));
    } finally {
      s(!1);
    }
  };
  return /* @__PURE__ */ o("div", { className: "mt-3", children: [
    /* @__PURE__ */ n("div", { className: "text-xs text-muted mb-1", children: a.programsHelp }),
    /* @__PURE__ */ o("div", { className: "flex flex-wrap gap-2 items-center", children: [
      e.programs.map((p) => /* @__PURE__ */ o("span", { className: "inline-flex items-center gap-1", children: [
        /* @__PURE__ */ n(D, { variant: "aim", children: p }),
        /* @__PURE__ */ n(
          "button",
          {
            type: "button",
            "aria-label": a.removeProgram(p),
            className: "text-xs text-muted hover:text-danger",
            disabled: r,
            onClick: () => {
              v(e.programs.filter((y) => y !== p));
            },
            children: "✕"
          }
        )
      ] }, p)),
      /* @__PURE__ */ n(A, { "aria-label": a.addProgramLabel(e.name || e.id), placeholder: a.programsPlaceholder, className: "max-w-[220px]", value: i, onChange: (p) => m(p.target.value) }),
      i.trim() && /* @__PURE__ */ n(C, { primary: !0, disabled: r, onClick: () => {
        const p = i.trim();
        m(""), v([...e.programs, p]);
      }, children: a.add })
    ] })
  ] });
}
function J({ people: e, caps: t, onSaved: g, onError: l }) {
  const i = (r) => r.maintainers.length ? 0 : r.commands.length || r.programs.length ? 1 : 2, m = [...e.channels].sort((r, s) => i(r) - i(s));
  return /* @__PURE__ */ o(N, { children: [
    /* @__PURE__ */ n(S, { children: a.maintainersTitle }),
    /* @__PURE__ */ n("ul", { className: "text-xs text-muted mb-2 list-disc pl-5 space-y-0.5", children: (t.confinement ? a.maintainersHelpConfined : a.maintainersHelp).map((r) => /* @__PURE__ */ n("li", { children: r }, r)) }),
    /* @__PURE__ */ n("div", { className: "text-sm", children: m.map((r) => /* @__PURE__ */ n(
      V,
      {
        ch: r,
        members: e.members,
        catalog: e.command_catalog,
        caps: t,
        onSaved: g,
        onError: l
      },
      `${r.id}:${r.maintainers.join(",")}:${r.commands.join(",")}:${r.programs.join(",")}`
    )) }),
    /* @__PURE__ */ n("p", { className: "text-xs text-muted mt-2 font-mono", children: e.roles_path })
  ] });
}
function Q({ settings: e, onSaved: t, onError: g }) {
  const l = _(), [i, m] = f(e);
  L(() => m(e), [e]);
  const r = async () => {
    try {
      await l.put(`${x}/settings`, i), t();
    } catch (s) {
      g(String(s));
    }
  };
  return /* @__PURE__ */ o(N, { children: [
    /* @__PURE__ */ n(S, { children: a.settingsTitle }),
    /* @__PURE__ */ o("div", { className: "grid gap-3 text-sm grid-cols-[180px_1fr] items-center", children: [
      /* @__PURE__ */ n("label", { htmlFor: "co-mode", children: a.detectMode }),
      /* @__PURE__ */ n(O, { label: a.detectMode, value: i.mode, options: ["auto", "notify", "off"], onChange: (s) => m({ ...i, mode: s }) }),
      /* @__PURE__ */ n("label", { htmlFor: "co-root", children: a.workspaceRoot }),
      /* @__PURE__ */ n(A, { id: "co-root", value: i.workspace_root, onChange: (s) => m({ ...i, workspace_root: s.target.value }) }),
      /* @__PURE__ */ n("span", { children: a.defaultActivation }),
      /* @__PURE__ */ n(O, { label: a.defaultActivation, value: i.activation, options: H, onChange: (s) => m({ ...i, activation: s }) }),
      /* @__PURE__ */ n("span", { children: a.defaultFollow }),
      /* @__PURE__ */ n($, { checked: i.thread_follow, onChange: (s) => m({ ...i, thread_follow: s }), label: a.defaultFollow }),
      /* @__PURE__ */ n("span", { children: a.ownerMember }),
      /* @__PURE__ */ n($, { checked: i.require_owner_member, onChange: (s) => m({ ...i, require_owner_member: s }), label: a.ownerMember }),
      /* @__PURE__ */ n("span", { children: a.dedicatedMemory }),
      /* @__PURE__ */ n($, { checked: i.dedicated_memory, onChange: (s) => m({ ...i, dedicated_memory: s }), label: a.dedicatedMemory }),
      /* @__PURE__ */ n("label", { htmlFor: "co-poll", children: a.pollSecs }),
      /* @__PURE__ */ n(A, { id: "co-poll", type: "number", min: 60, max: 3600, value: i.poll_secs, onChange: (s) => m({ ...i, poll_secs: Number(s.target.value) }) })
    ] }),
    /* @__PURE__ */ n("div", { className: "mt-3", children: /* @__PURE__ */ n(C, { primary: !0, onClick: r, children: a.saveSettings }) }),
    /* @__PURE__ */ n("p", { className: "text-xs text-muted mt-2", children: a.modeHelp })
  ] });
}
function te() {
  const e = _(), [t, g] = f(null), [l, i] = f(null), [m, r] = f(""), [s, v] = f(""), p = W(() => {
    r(""), e.get(`${x}/channels`).then(g).catch((d) => r(String(d))), e.get(`${x}/people`).then(i).catch((d) => r(String(d)));
  }, []);
  L(() => {
    p();
  }, [p]);
  const y = (d) => {
    v(d), p();
  }, h = (t == null ? void 0 : t.channels.filter((d) => d.configured)) ?? [], b = (t == null ? void 0 : t.channels.filter((d) => !d.configured && d.bot_member && !d.id.startsWith("D"))) ?? [], c = (l == null ? void 0 : l.capabilities) ?? G, k = new Set(((l == null ? void 0 : l.channels) ?? []).filter((d) => d.open).map((d) => d.id));
  return /* @__PURE__ */ o(R, { children: [
    /* @__PURE__ */ n(X, { title: "Slack Channels Onboard", subtitle: a.subtitle, actions: /* @__PURE__ */ n(C, { onClick: p, children: a.refresh }) }),
    /* @__PURE__ */ o("div", { className: "px-6 pb-8 overflow-y-auto flex-1 min-h-0 space-y-4", children: [
      m && /* @__PURE__ */ n(N, { children: /* @__PURE__ */ n("div", { role: "alert", className: "text-danger text-sm", children: m }) }),
      s && /* @__PURE__ */ n(N, { children: /* @__PURE__ */ n("div", { role: "status", className: "text-sm", children: s }) }),
      (t == null ? void 0 : t.slack_error) && /* @__PURE__ */ n(N, { children: /* @__PURE__ */ o("div", { role: "alert", className: "text-warn text-sm", children: [
        a.slackError,
        t.slack_error
      ] }) }),
      (l == null ? void 0 : l.roles_error) && /* @__PURE__ */ n(N, { children: /* @__PURE__ */ o("div", { role: "alert", className: "text-danger text-sm", children: [
        a.rolesError,
        l.roles_error
      ] }) }),
      /* @__PURE__ */ o("div", { className: "grid gap-3.5 grid-cols-[repeat(auto-fit,minmax(150px,1fr))]", children: [
        /* @__PURE__ */ n(P, { label: a.statConfigured, value: t ? h.length : null, accent: !0 }),
        /* @__PURE__ */ n(P, { label: a.statPending, value: t ? b.length : null }),
        c.open_channel && /* @__PURE__ */ n(P, { label: a.statOpen, value: l ? k.size : null }),
        /* @__PURE__ */ n(P, { label: a.statMode, value: t ? t.settings.mode : null })
      ] }),
      /* @__PURE__ */ o(N, { children: [
        /* @__PURE__ */ n(S, { children: a.pendingTitle }),
        t && b.length === 0 ? /* @__PURE__ */ n(B, { icon: "✓", title: a.pendingEmptyTitle, subtitle: a.pendingEmptySub }) : /* @__PURE__ */ n("table", { className: "w-full text-left", children: /* @__PURE__ */ n("tbody", { children: b.map((d) => t && /* @__PURE__ */ n(j, { row: d, settings: t.settings, onDone: p, onError: r }, d.id)) }) })
      ] }),
      /* @__PURE__ */ o(N, { children: [
        /* @__PURE__ */ n(S, { children: a.configuredTitle }),
        c.open_channel && /* @__PURE__ */ n("p", { className: "text-xs text-muted mb-2", children: a.openHelp }),
        /* @__PURE__ */ o("table", { className: "w-full text-left text-sm", children: [
          /* @__PURE__ */ n("thead", { children: /* @__PURE__ */ o("tr", { className: "text-xs text-muted", children: [
            /* @__PURE__ */ n("th", { className: "pb-2 pr-3", children: a.colChannel }),
            /* @__PURE__ */ n("th", { className: "pb-2 pr-3", children: a.colAgent }),
            /* @__PURE__ */ n("th", { className: "pb-2 pr-3", children: a.colWorkspace }),
            /* @__PURE__ */ n("th", { className: "pb-2 pr-3", children: a.colActivation }),
            /* @__PURE__ */ n("th", { className: "pb-2 pr-3", children: a.colFollow }),
            c.open_channel && /* @__PURE__ */ n("th", { className: "pb-2 pr-3", children: a.colOpen }),
            /* @__PURE__ */ n("th", { className: "pb-2" })
          ] }) }),
          /* @__PURE__ */ n("tbody", { children: h.map((d) => /* @__PURE__ */ n(U, { row: d, open: k.has(d.id), canOpen: c.open_channel, onSaved: p, onError: r }, `${d.id}:${d.workspace_dir}:${d.activation}:${d.thread_follow}:${k.has(d.id)}`)) })
        ] })
      ] }),
      l && !c.any && /* @__PURE__ */ o(N, { children: [
        /* @__PURE__ */ n(S, { children: a.peopleUnsupportedTitle }),
        /* @__PURE__ */ n("p", { className: "text-sm text-muted", children: a.peopleUnsupported })
      ] }),
      l && c.members && /* @__PURE__ */ n(K, { people: l, onSaved: y, onError: r }),
      l && c.maintainers && /* @__PURE__ */ n(J, { people: l, caps: c, onSaved: y, onError: r }),
      t && /* @__PURE__ */ n(Q, { settings: t.settings, onSaved: p, onError: r })
    ] })
  ] });
}
export {
  te as default
};
