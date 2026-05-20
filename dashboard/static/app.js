const $ = (id) => document.getElementById(id);
const token = window.WATCHDOG_ACTION_TOKEN || "";
let lastStatus = null;

function toast(message) {
  const node = $("toast");
  node.textContent = message;
  node.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { node.hidden = true; }, 3800);
}

function fmtAge(seconds) {
  if (seconds == null) return "missing";
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
      "X-Watchdog-Token": token,
    },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.ok === false) throw new Error(data.error || `request failed ${res.status}`);
  return data;
}

function drawBars(canvas, data) {
  const ctx = canvas.getContext("2d");
  const width = canvas.clientWidth || 480;
  const height = canvas.height;
  canvas.width = width * devicePixelRatio;
  canvas.height = height * devicePixelRatio;
  ctx.scale(devicePixelRatio, devicePixelRatio);
  ctx.clearRect(0, 0, width, height);
  const entries = Object.entries(data || {}).slice(0, 8);
  if (!entries.length) {
    ctx.fillStyle = "#7b8794";
    ctx.fillText("暂无异常分类", 12, 28);
    return;
  }
  const max = Math.max(...entries.map(([, value]) => value), 1);
  const colors = ["#2f6fbe", "#27845f", "#b86f00", "#c64242", "#7957b8", "#207b88", "#7d6b24", "#b64e7d"];
  entries.forEach(([name, value], index) => {
    const y = 18 + index * 20;
    const barWidth = Math.max(4, (width - 180) * (value / max));
    ctx.fillStyle = colors[index % colors.length];
    ctx.fillRect(132, y - 10, barWidth, 11);
    ctx.fillStyle = getComputedStyle(document.documentElement).getPropertyValue("--muted");
    ctx.font = "12px ui-monospace, Consolas, monospace";
    ctx.fillText(name, 8, y);
    ctx.fillText(String(value), 142 + barWidth, y);
  });
}

function drawTimeline(canvas, diagnostics, modelHistory) {
  const ctx = canvas.getContext("2d");
  const width = canvas.clientWidth || 700;
  const height = canvas.height;
  canvas.width = width * devicePixelRatio;
  canvas.height = height * devicePixelRatio;
  ctx.scale(devicePixelRatio, devicePixelRatio);
  ctx.clearRect(0, 0, width, height);
  const points = [];
  for (const item of diagnostics || []) {
    points.push({ ts: Date.parse(item.ts), kind: item.newLogSignals ? "warn" : "ok" });
  }
  for (const item of modelHistory || []) {
    points.push({ ts: Date.parse(item.ts), kind: item.status === "fail" ? "fail" : "model-ok" });
  }
  const valid = points.filter((p) => Number.isFinite(p.ts)).sort((a, b) => a.ts - b.ts).slice(-120);
  const left = 34, right = width - 16, top = 18, bottom = height - 28;
  ctx.strokeStyle = getComputedStyle(document.documentElement).getPropertyValue("--line");
  ctx.beginPath();
  ctx.moveTo(left, bottom);
  ctx.lineTo(right, bottom);
  ctx.stroke();
  if (!valid.length) {
    ctx.fillStyle = "#7b8794";
    ctx.fillText("暂无时间线数据", left, top + 18);
    return;
  }
  const min = valid[0].ts;
  const max = valid[valid.length - 1].ts || min + 1;
  const color = { ok: "#27845f", warn: "#b86f00", fail: "#c64242", "model-ok": "#2f6fbe" };
  valid.forEach((p, index) => {
    const x = left + ((p.ts - min) / Math.max(1, max - min)) * (right - left);
    const y = p.kind === "fail" ? top + 14 : p.kind === "warn" ? top + 50 : p.kind === "model-ok" ? top + 86 : top + 118;
    ctx.fillStyle = color[p.kind] || "#7b8794";
    ctx.beginPath();
    ctx.arc(x, y, index === valid.length - 1 ? 4.5 : 3.2, 0, Math.PI * 2);
    ctx.fill();
  });
  ctx.fillStyle = getComputedStyle(document.documentElement).getPropertyValue("--muted");
  ctx.font = "12px system-ui";
  ctx.fillText("API失败", 36, top + 18);
  ctx.fillText("日志WARN", 36, top + 54);
  ctx.fillText("模型OK", 36, top + 90);
  ctx.fillText("诊断OK", 36, top + 122);
}

function renderLayers(data) {
  const files = data.files || {};
  const cfg = data.config || {};
  const layers = [
    ["Gateway", files.gateway, data.summary.status === "ok" ? "ok" : data.summary.status === "unknown" ? "warn" : "fail"],
    ["OpenClaw Health", files.health, data.summary.status === "degraded" ? "fail" : files.health?.exists ? "ok" : "warn"],
    ["Logs Signal", files.signals, data.summary.categoryCount ? "warn" : "ok"],
    ["Model Probe", files.modelHistory, data.summary.modelFailures ? "warn" : files.modelHistory?.exists ? "ok" : "warn"],
    ["Config", { exists: true, ageSeconds: null }, cfg.MODEL_PROBE_ENABLED === "1" || cfg.ModelProbeEnabled === true ? "warn" : "ok"],
  ];
  $("layers").innerHTML = layers.map(([name, meta, state]) => `
    <div class="layer">
      <span class="spark ${state}"></span>
      <div><strong>${name}</strong><span class="muted">${meta?.path || "runtime snapshot"}</span></div>
      <span class="muted">${meta?.exists ? fmtAge(meta.ageSeconds) : "missing"}</span>
    </div>
  `).join("");
}

function renderConfig(config) {
  const keys = [
    "OPENCLAW_DIAG_ACTION", "MODEL_PROBE_ENABLED", "MODEL_PROBE_INTERVAL",
    "MODEL_PROBE_ACTION", "CHANNEL_FAILURES_BEFORE_RESTART", "MAX_RESTARTS_PER_HOUR",
    "DashboardEnabled", "DashboardPort", "DashboardActionsEnabled",
  ];
  const rows = [];
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(config, key)) rows.push([key, config[key]]);
  }
  $("configList").innerHTML = rows.map(([key, value]) => `<dt>${key}</dt><dd>${String(value)}</dd>`).join("");
}

function renderFiles(files) {
  $("fileList").innerHTML = Object.entries(files || {}).map(([name, meta]) => `
    <div class="file-row">
      <strong>${name}</strong>
      <span class="muted">${meta.exists ? `${fmtAge(meta.ageSeconds)} · ${Math.round((meta.size || 0) / 1024)}KB` : "missing"}</span>
    </div>
  `).join("");
}

function render(data) {
  lastStatus = data;
  const status = data.summary.status || "unknown";
  $("mainStatus").className = `status-dot ${statusClass(status)}`;
  $("statusText").textContent = status.toUpperCase();
  $("statusReason").textContent = data.summary.reason || "No reason yet.";
  $("restartCount").textContent = data.summary.recentRestarts ?? 0;
  $("categoryCount").textContent = data.summary.categoryCount ?? 0;
  $("modelOk").textContent = data.summary.modelOk ?? 0;
  $("modelFail").textContent = data.summary.modelFailures ?? 0;
  $("updatedAt").textContent = new Date(data.generatedAt).toLocaleString();
  $("actionState").textContent = data.dashboard.actionsEnabled ? "可执行" : "只读";
  $("actionState").className = data.dashboard.actionsEnabled ? "pill enabled" : "pill";
  renderLayers(data);
  renderConfig(data.config || {});
  renderFiles(data.files || {});
  $("logTail").textContent = (data.logTail || []).join("\n") || "暂无日志。";
  drawBars($("categoryChart"), data.categories || {});
  drawTimeline($("timelineChart"), data.diagnostics || [], data.modelHistory || []);
}

async function refresh() {
  try {
    render(await fetchStatus());
  } catch (err) {
    toast(`刷新失败: ${err.message}`);
  }
}

$("refreshBtn").addEventListener("click", refresh);
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
    toast("正在执行诊断...");
    await postJson("/api/actions/run-diagnostics");
    await refresh();
    toast("诊断完成");
  } catch (err) {
    toast(err.message);
  }
});
$("restartBtn").addEventListener("click", async () => {
  if (!confirm("确认重启 OpenClaw Gateway？")) return;
  try {
    await postJson("/api/actions/restart-gateway");
    await refresh();
    toast("重启命令已执行");
  } catch (err) {
    toast(err.message);
  }
});
document.querySelectorAll("[data-preset]").forEach((button) => {
  button.addEventListener("click", async () => {
    try {
      await postJson("/api/config/preset", { preset: button.dataset.preset });
      await refresh();
      toast(`已切换策略: ${button.textContent}`);
    } catch (err) {
      toast(err.message);
    }
  });
});

refresh();
setInterval(refresh, 15000);
