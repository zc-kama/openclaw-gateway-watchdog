const $ = (id) => document.getElementById(id);

const DICT = {
  zh: {
    brandSub: "OpenClaw 看门狗",
    navOverview: "总览",
    navEvents: "趋势",
    navStrategy: "策略",
    navLogs: "日志",
    sideNote: "独立运行在 localhost，Gateway 挂了也能打开。",
    pageTitle: "恢复控制台",
    export: "导出诊断",
    currentDecision: "当前判断",
    recentRestarts: "近期重启",
    signalTypes: "异常类别",
    modelOk: "模型成功",
    modelFail: "模型失败",
    layers: "链路分层",
    signalCategories: "异常分类",
    eventTrend: "事件趋势",
    eventTrendHint: "诊断与模型探针",
    quickStrategy: "快速策略",
    unlock: "解锁操作",
    lock: "锁定操作",
    presetObserve: "观察模式",
    presetOvernight: "夜间诊断",
    presetChannel: "通道恢复",
    presetConservative: "保守熔断",
    strategyTip: "悬停策略按钮查看说明。",
    tipObserve: "只记录证据，不主动改变策略，适合先观察问题。",
    tipOvernight: "开启轻量模型探针并保持 log-only，适合排查固定时段超时。",
    tipChannel: "保持通道恢复敏感度，适合通道/session 经常断开的场景。",
    tipConservative: "提高阈值并降低重启频率，适合网络不稳定时防止重启风暴。",
    runDiag: "立即诊断",
    restartGateway: "重启 Gateway",
    configSummary: "配置摘要",
    sensitiveMasked: "敏感项已遮盖",
    stateFiles: "状态文件",
    recentLogs: "最近日志",
    followLatest: "保持最新",
    locked: "只读",
    actionReady: "可执行",
    unlocked: "已解锁",
    missing: "缺失",
    noSignals: "暂无异常分类",
    noTimeline: "暂无趋势数据",
    refreshFailed: "刷新失败",
    runningDiag: "正在执行诊断...",
    diagDone: "诊断完成",
    restartConfirm: "确认重启 OpenClaw Gateway？",
    restartDone: "重启命令已执行",
    presetDone: "已切换策略",
    tokenPrompt: "请输入 watchdog dashboard token。可在 watchdog.env/json 中查看 DASHBOARD_TOKEN。",
    tokenSaved: "操作 token 已保存到当前浏览器。",
    tokenCleared: "已清除本地 token。",
    clearConfirm: "要清除当前浏览器保存的操作 token 吗？",
    statusUnknown: "正在汇总 watchdog 状态。",
    xAxis: "时间",
    apiFail: "API失败",
    logWarn: "日志WARN",
    modelOkLegend: "模型OK",
    diagOk: "诊断OK",
  },
  en: {
    brandSub: "OpenClaw Watchdog",
    navOverview: "Overview",
    navEvents: "Trends",
    navStrategy: "Strategy",
    navLogs: "Logs",
    sideNote: "Runs on localhost and stays reachable when Gateway is down.",
    pageTitle: "Recovery Console",
    export: "Export Diagnostics",
    currentDecision: "Current Decision",
    recentRestarts: "Recent Restarts",
    signalTypes: "Signal Types",
    modelOk: "Model OK",
    modelFail: "Model Failed",
    layers: "Health Layers",
    signalCategories: "Signal Categories",
    eventTrend: "Event Trend",
    eventTrendHint: "Diagnostics and model probes",
    quickStrategy: "Quick Strategy",
    unlock: "Unlock Actions",
    lock: "Lock Actions",
    presetObserve: "Observe",
    presetOvernight: "Overnight Diagnosis",
    presetChannel: "Channel Recovery",
    presetConservative: "Conservative Breaker",
    strategyTip: "Hover a strategy button to see what it changes.",
    tipObserve: "Record evidence only. Best when you want to observe first.",
    tipOvernight: "Enable lightweight model probes with log-only actions for fixed-hour timeouts.",
    tipChannel: "Keep channel recovery responsive for session or channel disconnects.",
    tipConservative: "Raise thresholds and reduce restart frequency to prevent restart storms.",
    runDiag: "Run Diagnostics",
    restartGateway: "Restart Gateway",
    configSummary: "Config Summary",
    sensitiveMasked: "Sensitive values are masked",
    stateFiles: "State Files",
    recentLogs: "Recent Logs",
    followLatest: "Follow latest",
    locked: "Read-only",
    actionReady: "Action ready",
    unlocked: "Unlocked",
    missing: "missing",
    noSignals: "No signal categories yet",
    noTimeline: "No trend data yet",
    refreshFailed: "Refresh failed",
    runningDiag: "Running diagnostics...",
    diagDone: "Diagnostics complete",
    restartConfirm: "Restart OpenClaw Gateway?",
    restartDone: "Restart command executed",
    presetDone: "Strategy applied",
    tokenPrompt: "Enter the watchdog dashboard token from DASHBOARD_TOKEN in watchdog.env/json.",
    tokenSaved: "Action token saved in this browser.",
    tokenCleared: "Local token cleared.",
    clearConfirm: "Clear the action token saved in this browser?",
    statusUnknown: "Collecting watchdog status.",
    xAxis: "Time",
    apiFail: "API failed",
    logWarn: "Log WARN",
    modelOkLegend: "Model OK",
    diagOk: "Diag OK",
  },
};

let lang = localStorage.getItem("watchdog.lang") || "zh";
let theme = localStorage.getItem("watchdog.theme") || "light";
let actionToken = localStorage.getItem("watchdog.actionToken") || window.WATCHDOG_ACTION_TOKEN || "";
let lastStatus = null;

function t(key) {
  return DICT[lang]?.[key] || DICT.zh[key] || key;
}

function applyLocale() {
  document.documentElement.lang = lang === "zh" ? "zh-CN" : "en";
  $("langSelect").value = lang;
  document.querySelectorAll("[data-i18n]").forEach((node) => {
    node.textContent = t(node.dataset.i18n);
  });
  document.querySelectorAll("[data-tip-key]").forEach((node) => {
    node.title = t(node.dataset.tipKey);
  });
}

function applyTheme() {
  document.documentElement.dataset.theme = theme;
  $("themeSelect").value = theme;
}

function toast(message) {
  const node = $("toast");
  node.textContent = message;
  node.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { node.hidden = true; }, 3800);
}

function fmtAge(seconds) {
  if (seconds == null) return t("missing");
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}m`;
  return `${Math.round(seconds / 3600)}h`;
}

function statusClass(status) {
  if (status === "ok") return "ok";
  if (status === "degraded" || status === "stale") return "degraded";
  if (status === "down" || status === "fail") return "fail";
  return "unknown";
}

async function fetchStatus() {
  const res = await fetch("/api/status", { cache: "no-store" });
  if (!res.ok) throw new Error(`status ${res.status}`);
  return res.json();
}

async function postJson(url, body = {}) {
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Watchdog-Token": actionToken,
    },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.ok === false) throw new Error(data.error || `request failed ${res.status}`);
  return data;
}

function prepareCanvas(canvas, fallbackHeight) {
  const rect = canvas.getBoundingClientRect();
  const width = Math.max(320, Math.floor(rect.width || canvas.clientWidth || 480));
  const cssHeight = Math.max(140, Math.floor(rect.height || fallbackHeight));
  const ratio = window.devicePixelRatio || 1;
  canvas.width = Math.floor(width * ratio);
  canvas.height = Math.floor(cssHeight * ratio);
  const ctx = canvas.getContext("2d");
  ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
  ctx.clearRect(0, 0, width, cssHeight);
  return { ctx, width, height: cssHeight };
}

function cssVar(name) {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

function drawBars(canvas, data) {
  const { ctx, width, height } = prepareCanvas(canvas, 206);
  const entries = Object.entries(data || {}).slice(0, 8);
  ctx.font = "12px ui-monospace, Consolas, monospace";
  if (!entries.length) {
    ctx.fillStyle = cssVar("--muted");
    ctx.fillText(t("noSignals"), 14, 28);
    return;
  }
  const max = Math.max(...entries.map(([, value]) => value), 1);
  const colors = [cssVar("--accent"), cssVar("--green"), cssVar("--amber"), cssVar("--red"), cssVar("--violet"), cssVar("--accent-2")];
  const labelWidth = Math.min(150, Math.max(108, width * 0.34));
  const rowHeight = Math.max(18, Math.floor((height - 26) / entries.length));
  entries.forEach(([name, value], index) => {
    const y = 20 + index * rowHeight;
    const barWidth = Math.max(4, (width - labelWidth - 48) * (value / max));
    ctx.fillStyle = cssVar("--muted");
    ctx.fillText(name.length > 18 ? `${name.slice(0, 17)}…` : name, 12, y);
    ctx.fillStyle = colors[index % colors.length];
    ctx.fillRect(labelWidth, y - 11, barWidth, 12);
    ctx.fillStyle = cssVar("--ink");
    ctx.fillText(String(value), labelWidth + barWidth + 8, y);
  });
}

function formatTick(ts) {
  return new Date(ts).toLocaleTimeString(lang === "zh" ? "zh-CN" : "en-US", { hour: "2-digit", minute: "2-digit" });
}

function drawTimeline(canvas, diagnostics, modelHistory) {
  const { ctx, width, height } = prepareCanvas(canvas, 224);
  const points = [];
  for (const item of diagnostics || []) points.push({ ts: Date.parse(item.ts), kind: item.newLogSignals ? "warn" : "ok" });
  for (const item of modelHistory || []) points.push({ ts: Date.parse(item.ts), kind: item.status === "fail" ? "fail" : "model-ok" });
  const valid = points.filter((p) => Number.isFinite(p.ts)).sort((a, b) => a.ts - b.ts).slice(-160);
  const left = 92, right = width - 18, top = 24, axisY = height - 34;
  ctx.font = "12px system-ui";
  ctx.strokeStyle = cssVar("--line");
  ctx.fillStyle = cssVar("--muted");
  ctx.beginPath();
  ctx.moveTo(left, axisY);
  ctx.lineTo(right, axisY);
  ctx.stroke();
  ctx.fillText(t("xAxis"), right - 28, axisY + 22);
  if (!valid.length) {
    ctx.fillText(t("noTimeline"), left, top + 28);
    return;
  }
  const min = valid[0].ts;
  const max = valid[valid.length - 1].ts || min + 1;
  const lanes = [
    ["fail", t("apiFail"), cssVar("--red"), top + 18],
    ["warn", t("logWarn"), cssVar("--amber"), top + 58],
    ["model-ok", t("modelOkLegend"), cssVar("--accent"), top + 98],
    ["ok", t("diagOk"), cssVar("--green"), top + 138],
  ];
  for (const [, label, color, y] of lanes) {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(18, y - 4, 4, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = cssVar("--muted");
    ctx.fillText(label, 30, y);
    ctx.strokeStyle = cssVar("--line");
    ctx.beginPath();
    ctx.moveTo(left, y - 4);
    ctx.lineTo(right, y - 4);
    ctx.stroke();
  }
  const laneMap = Object.fromEntries(lanes.map(([kind, , color, y]) => [kind, { color, y: y - 4 }]));
  valid.forEach((p, index) => {
    const x = left + ((p.ts - min) / Math.max(1, max - min)) * (right - left);
    const lane = laneMap[p.kind] || laneMap.ok;
    ctx.fillStyle = lane.color;
    ctx.beginPath();
    ctx.arc(x, lane.y, index === valid.length - 1 ? 4.6 : 3.3, 0, Math.PI * 2);
    ctx.fill();
  });
  const ticks = [min, min + (max - min) / 2, max];
  ctx.fillStyle = cssVar("--muted");
  ticks.forEach((tick, i) => {
    const x = left + ((tick - min) / Math.max(1, max - min)) * (right - left);
    const label = formatTick(tick);
    ctx.fillText(label, i === 2 ? x - 38 : x - 12, axisY + 18);
  });
}

function renderLayers(data) {
  const files = data.files || {};
  const cfg = data.config || {};
  const layers = [
    ["Gateway", files.gateway, data.summary.status === "ok" ? "ok" : data.summary.status === "unknown" ? "warn" : "fail"],
    ["OpenClaw Health", files.health, data.summary.status === "degraded" ? "fail" : files.health?.exists ? "ok" : "warn"],
    ["Logs Signal", files.signals, data.summary.categoryCount ? "warn" : "ok"],
    ["Model Probe", files.modelHistory, data.summary.modelFailures ? "warn" : files.modelHistory?.exists ? "ok" : "warn"],
    ["Config", { exists: true, ageSeconds: null, path: data.configFile }, cfg.MODEL_PROBE_ENABLED === "1" || cfg.ModelProbeEnabled === true ? "warn" : "ok"],
  ];
  $("layers").innerHTML = layers.map(([name, meta, state]) => `
    <div class="layer">
      <span class="spark ${state}"></span>
      <div><strong>${name}</strong><span class="muted" title="${meta?.path || ""}">${meta?.path || "runtime snapshot"}</span></div>
      <span class="muted">${meta?.exists ? fmtAge(meta.ageSeconds) : t("missing")}</span>
    </div>
  `).join("");
}

function renderConfig(config) {
  const keys = [
    "OPENCLAW_DIAG_ACTION", "MODEL_PROBE_ENABLED", "MODEL_PROBE_INTERVAL",
    "MODEL_PROBE_ACTION", "CHANNEL_FAILURES_BEFORE_RESTART", "MAX_RESTARTS_PER_HOUR",
    "DASHBOARD_ACTIONS_ENABLED", "DashboardActionsEnabled", "DASHBOARD_PORT", "DashboardPort",
  ];
  const rows = [];
  for (const key of keys) if (Object.prototype.hasOwnProperty.call(config, key)) rows.push([key, config[key]]);
  $("configList").innerHTML = rows.map(([key, value]) => `<dt>${key}</dt><dd>${String(value)}</dd>`).join("");
}

function renderFiles(files) {
  $("fileList").innerHTML = Object.entries(files || {}).map(([name, meta]) => `
    <div class="file-row">
      <strong>${name}</strong>
      <span class="muted">${meta.exists ? `${fmtAge(meta.ageSeconds)} · ${Math.round((meta.size || 0) / 1024)}KB` : t("missing")}</span>
    </div>
  `).join("");
}

function updateActionUi(data) {
  const serverReady = Boolean(data.dashboard?.actionsEnabled);
  const unlocked = Boolean(actionToken);
  $("actionState").textContent = serverReady ? (unlocked ? t("unlocked") : t("actionReady")) : t("locked");
  $("actionState").className = serverReady ? (unlocked ? "pill unlocked" : "pill enabled") : "pill";
  $("unlockBtn").textContent = unlocked ? t("lock") : t("unlock");
  const disabled = !serverReady || !unlocked;
  document.querySelectorAll("[data-preset], #diagBtn, #restartBtn").forEach((node) => { node.disabled = disabled; });
}

function render(data) {
  lastStatus = data;
  const status = data.summary.status || "unknown";
  $("mainStatus").className = `status-dot ${statusClass(status)}`;
  $("statusText").textContent = status.toUpperCase();
  $("statusReason").textContent = data.summary.reason || t("statusUnknown");
  $("restartCount").textContent = data.summary.recentRestarts ?? 0;
  $("categoryCount").textContent = data.summary.categoryCount ?? 0;
  $("modelOk").textContent = data.summary.modelOk ?? 0;
  $("modelFail").textContent = data.summary.modelFailures ?? 0;
  $("updatedAt").textContent = new Date(data.generatedAt).toLocaleString(lang === "zh" ? "zh-CN" : "en-US");
  updateActionUi(data);
  renderLayers(data);
  renderConfig(data.config || {});
  renderFiles(data.files || {});
  const log = $("logTail");
  const shouldFollow = $("followLog").checked;
  log.textContent = (data.logTail || []).join("\n") || "No logs yet.";
  if (shouldFollow) log.scrollTop = log.scrollHeight;
  drawBars($("categoryChart"), data.categories || {});
  drawTimeline($("timelineChart"), data.diagnostics || [], data.modelHistory || []);
}

async function refresh() {
  try {
    render(await fetchStatus());
  } catch (err) {
    toast(`${t("refreshFailed")}: ${err.message}`);
  }
}

function saveSettings() {
  localStorage.setItem("watchdog.lang", lang);
  localStorage.setItem("watchdog.theme", theme);
}

$("langSelect").addEventListener("change", () => {
  lang = $("langSelect").value;
  saveSettings();
  applyLocale();
  if (lastStatus) render(lastStatus);
});

$("themeSelect").addEventListener("change", () => {
  theme = $("themeSelect").value;
  saveSettings();
  applyTheme();
  if (lastStatus) render(lastStatus);
});

$("refreshBtn").addEventListener("click", refresh);
$("unlockBtn").addEventListener("click", () => {
  if (actionToken) {
    if (confirm(t("clearConfirm"))) {
      actionToken = "";
      localStorage.removeItem("watchdog.actionToken");
      toast(t("tokenCleared"));
      if (lastStatus) render(lastStatus);
    }
    return;
  }
  const entered = prompt(t("tokenPrompt"), "");
  if (entered && entered.trim()) {
    actionToken = entered.trim();
    localStorage.setItem("watchdog.actionToken", actionToken);
    toast(t("tokenSaved"));
    if (lastStatus) render(lastStatus);
  }
});

$("exportBtn").addEventListener("click", async () => {
  const data = lastStatus || await fetchStatus();
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `openclaw-watchdog-${Date.now()}.json`;
  a.click();
  URL.revokeObjectURL(url);
});

$("diagBtn").addEventListener("click", async () => {
  try {
    toast(t("runningDiag"));
    await postJson("/api/actions/run-diagnostics");
    await refresh();
    toast(t("diagDone"));
  } catch (err) {
    toast(err.message);
  }
});

$("restartBtn").addEventListener("click", async () => {
  if (!confirm(t("restartConfirm"))) return;
  try {
    await postJson("/api/actions/restart-gateway");
    await refresh();
    toast(t("restartDone"));
  } catch (err) {
    toast(err.message);
  }
});

document.querySelectorAll("[data-preset]").forEach((button) => {
  button.addEventListener("mouseenter", () => { $("strategyTip").textContent = t(button.dataset.tipKey); });
  button.addEventListener("focus", () => { $("strategyTip").textContent = t(button.dataset.tipKey); });
  button.addEventListener("mouseleave", () => { $("strategyTip").textContent = t("strategyTip"); });
  button.addEventListener("click", async () => {
    try {
      await postJson("/api/config/preset", { preset: button.dataset.preset });
      await refresh();
      toast(`${t("presetDone")}: ${button.textContent}`);
    } catch (err) {
      toast(err.message);
    }
  });
});

applyTheme();
applyLocale();
refresh();
setInterval(refresh, 15000);
