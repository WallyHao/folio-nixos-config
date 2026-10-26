"use strict";
const $ = (id) => document.getElementById(id);
const token = location.hash.slice(1) || sessionStorage.getItem("folio-panel-token") || "";
if (location.hash) { sessionStorage.setItem("folio-panel-token", token); history.replaceState(null, "", "/"); }
const state = {page: "wifi", wifi: null, devices: null, proxy: null, network: "", delays: new Map(), busy: false, testing: false, stopTesting: false};
const descriptions = {wifi: ["Wi-Fi", "Manage wireless networks and connections."], proxy: ["Proxy", "Choose a routing mode and manage proxy nodes."], devices: ["Sound & display", "Manage sound outputs and display brightness."], information: ["Device", "Hardware, operating system and connection details."], apps: ["Software", "Find, install and manage Flatpak applications."], settings: ["Settings", "Save personal preferences and review their inherited defaults."]};
function element(tag, cls, text) { const node = document.createElement(tag); if (cls) node.className = cls; if (text !== undefined) node.textContent = String(text); return node; }
function message(text, error = false) { $("notice").hidden = !text; $("notice").textContent = text; $("notice").className = error ? "error" : ""; }
async function api(path, body) {
  const response = await fetch("/api/" + path, {method: body ? "POST" : "GET", headers: {Authorization: "Bearer " + token, ...(body ? {"Content-Type": "application/json"} : {})}, body: body ? JSON.stringify(body) : undefined, cache: "no-store"});
  const reply = await response.json(); if (!response.ok) throw new Error([reply.error || "Service unavailable", reply.hint].filter(Boolean).join(" ")); return reply.data;
}
function options(id, entries, preferred) {
  const select = $(id), previous = preferred ?? select.value;
  select.replaceChildren(...entries.map(([value, label]) => { const option = element("option", "", label); option.value = value; return option; }));
  if (entries.some(([value]) => value === previous)) select.value = previous;
  select.disabled = !entries.length;
}
function details(node, rows) { node.replaceChildren(); for (const [key, value] of rows) node.append(element("dt", "", key), element("dd", "", value ?? "Unavailable")); }
function adapter() { return state.wifi?.adapters?.find((item) => item.interface === $("adapter").value); }
function network() { return adapter()?.networks?.find((item) => item.path === state.network); }
function empty(id, text) { $(id).replaceChildren(element("p", "empty", text)); }
function signal(percent) { const node = element("span", "signal"); node.setAttribute("aria-label", `Signal ${percent}%`); for (let i = 0; i < 4; i++) node.append(element("i", percent > i * 25 ? "on" : "")); return node; }
function wifiDetail() {
  const selected = network(), a = adapter(), writable = !!a && !!state.wifi?.enabled && !!state.wifi?.hardwareEnabled && !state.busy;
  $("network-name").textContent = selected?.ssid || (selected ? "Hidden network" : "Select a network");
  $("network-description").textContent = selected ? (selected.active ? "You are connected to this network." : selected.profiles?.length ? "A saved connection is available." : "Ready when you are.") : "Choose a network from the list.";
  details($("network-details"), selected ? [["Signal", selected.signal + "%"], ["Security", selected.security], ["Adapter", a.interface], ...((selected.active ? a.addresses : []) || []).map((address) => ["Address", address])] : []);
  $("connect").disabled = !writable || !selected || selected.active || !["Open", "WPA Personal", "WPA3"].includes(selected.security);
  $("disconnect").disabled = !writable || a.state !== "connected";
  $("forget").disabled = !writable || !selected?.profiles?.length;
  $("radio").disabled = !state.wifi || !state.wifi.hardwareEnabled || state.busy;
  $("radio").textContent = state.wifi?.enabled ? "Turn off Wi-Fi" : "Turn on Wi-Fi";
  for (const id of ["scan", "hidden-network"]) $(id).disabled = !writable;
}
function renderWifi() {
  const data = state.wifi;
  options("adapter", (data?.adapters || []).map((a) => [a.interface, a.interface]));
  const a = adapter();
  $("wifi-status").textContent = !data ? "Unavailable" : !data.hardwareEnabled ? "Hardware radio blocked" : !data.enabled ? "Wi-Fi off" : !a ? "No Wi-Fi adapter" : a.state;
  const networks = a?.networks || [];
  if (!networks.some((n) => n.path === state.network)) state.network = networks.find((n) => n.active)?.path || networks[0]?.path || "";
  $("networks").replaceChildren();
  for (const n of networks) {
    const row = element("button", "network-row" + (n.path === state.network ? " selected" : "")); row.type = "button"; row.setAttribute("aria-pressed", String(n.path === state.network));
    const main = element("span", "row-main"); main.append(element("span", "row-title", n.ssid || "Hidden network"), element("div", "row-subtitle", n.security));
    row.append(signal(n.signal), main, element("span", "row-end", n.active ? "Connected" : n.profiles?.length ? "Saved" : n.signal + "%"));
    row.onclick = () => { state.network = n.path; renderWifi(); }; $("networks").append(row);
  }
  if (!networks.length) empty("networks", !data ? "Wi-Fi service unavailable." : !data.enabled ? "Turn on Wi-Fi to discover networks." : "No nearby networks. Try scanning again.");
  wifiDetail();
}
function proxyNodes() {
  const groups = state.proxy?.groups || [], byName = new Map(groups.map(g => [g.name, g]));
  const primary = byName.get("PROXY") || groups.find(g => g.name !== "GLOBAL") || groups[0];
  if (!primary) return [];
  const global = byName.get("GLOBAL"), prefix = state.proxy.proxy.mode === "global" && global && global !== primary && global.nodes.includes(primary.name) ? [{group: global, node: primary.name}] : [];
  const nodes = new Map();
  function visit(g, path, seen) {
    if (seen.has(g.name)) return;
    const visited = new Set([...seen, g.name]);
    for (const name of g.nodes || []) {
      const steps = [...path, {group: g, node: name}];
      if (byName.has(name)) visit(byName.get(name), steps, visited);
      else if (!nodes.has(name)) nodes.set(name, {name, steps, selected: steps.every(step => step.group.selected === step.node)});
    }
  }
  visit(primary, prefix, new Set());
  if (prefix.length && global.nodes.includes("DIRECT") && nodes.has("DIRECT")) {
    nodes.set("DIRECT", {name: "DIRECT", steps: [{group: global, node: "DIRECT"}], selected: global.selected === "DIRECT"});
  }
  return [...nodes.values()];
}
function renderProxy() {
  const data = state.proxy, nodes = proxyNodes();
  $("proxy-status").textContent = !data ? "Proxy unavailable" : {direct: "Current: Direct", rule: "Current: Rule", global: "Current: Global"}[data.proxy.mode] || data.proxy.mode;
  if (data) $("mode").value = data.proxy.mode;
  $("mode").disabled = !data || state.busy || state.testing;
  $("test-all").disabled = !nodes.length || state.busy || state.stopTesting;
  $("test-all").textContent = state.stopTesting ? "Stopping…" : state.testing ? "Stop tests" : "Test all";
  $("proxy-description").textContent = data?.proxy.mode === "direct" ? "All traffic connects directly. Your node selection will be used in Rule or Global mode." : "Choose Use to switch nodes. The current node is marked Selected.";
  $("nodes").replaceChildren();
  for (const n of nodes) {
    const row = element("div", "node-row" + (n.selected ? " selected" : ""));
    const main = element("div", "row-main"); main.append(element("div", "row-title", n.name), element("div", "row-subtitle", n.selected ? "Selected" : "Available node"));
    const actions = element("div", "node-actions");
    const delay = element("span", "row-end", state.delays.get(n.name) || "Not tested");
    const test = element("button", "subtle", "Test"); test.disabled = state.busy || state.testing; test.onclick = () => testNodes([n.name]);
    const choose = element("button", n.selected ? "subtle" : "primary", n.selected ? "Selected" : "Use"); choose.disabled = state.busy || state.testing || n.selected;
    choose.onclick = () => selectProxy(n.steps);
    actions.append(delay, test, choose); row.append(main, actions); $("nodes").append(row);
  }
  if (!nodes.length) empty("nodes", data ? "No nodes available. Check that your subscription has loaded." : "Proxy service unavailable. Check Mihomo and the network backend.");
}
async function selectProxy(steps) {
  if (state.busy || state.testing) return;
  state.busy = true; generation++; renderProxy(); message("Switching node…");
  let success = false;
  try {
    // Set the leaf first, then route parent groups to it (GLOBAL → PROXY).
    for (const step of [...steps].reverse()) await api("action", {domain: "proxy", action: "proxy-group-select", fields: {group: step.group.name, node: step.node}});
    success = true;
  } catch (error) { message(error.message, true); }
  finally { state.busy = false; await refresh(true); renderProxy(); }
  if (success) message("Node selected.");
}
function renderDevices() {
  const data = state.devices, audio = data?.audio;
  const sink = audio?.sinks?.find((s) => s.name === audio.default);
  options("output", (audio?.sinks || []).map((s) => [s.name, s.description]), document.activeElement === $("output") ? undefined : audio?.default);
  $("set-output").disabled = !audio?.sinks?.length || state.busy; $("mute").disabled = !sink || state.busy;
  $("mute").textContent = sink?.mute ? "Unmute" : "Mute";
  $("volume").disabled = !sink || state.busy;
  if (sink && document.activeElement !== $("volume")) $("volume").value = Math.min(100, sink.volume);
  $("volume-value").textContent = sink ? `${$("volume").value}%${sink.mute ? " · muted" : ""}` : "Unavailable";
  options("backlight", (data?.backlights || []).map((b) => [b.name, b.name])); renderBacklight();
}
function renderBacklight() {
  const backlight = state.devices?.backlights?.find((b) => b.name === $("backlight").value);
  $("brightness").disabled = !backlight || state.busy;
  if (backlight && document.activeElement !== $("brightness")) $("brightness").value = backlight.percent;
  $("brightness-value").textContent = backlight ? $("brightness").value + "%" : "Unavailable";
  $("backlight-note").textContent = backlight ? "Changes apply to this backlight." : "No supported backlight on this device.";
}
function renderInformation(data) {
  $("information-content").replaceChildren();
  if (!data) { empty("information-content", "Device information unavailable."); return; }
  const gib = (n) => n ? (n / 1048576).toFixed(1) + " GiB" : "Unavailable";
  const groups = [
    ["COMPUTER", "Hardware overview", [["Model", data.model], ["Board", data.board], ["CPU", data.cpu], ["Memory", `${gib(data.memoryKiB)} total · ${gib(data.availableMemoryKiB)} available`]]],
    ["SYSTEM", "Operating system", [["OS", data.os], ["Kernel", data.kernel], ["Target", data.target], ["Uptime", Math.round((data.uptimeSeconds || 0) / 60) + " minutes"]]],
    ["GRAPHICS", "Graphics & displays", [...(data.gpus || []).map((g) => ["GPU", `${g.name} · ${g.driver}`]), ...(data.displays || []).map((d) => [d.name, (d.modes || []).slice(0, 3).join(", ")])]],
    ["CONNECTIONS", "Network & power", [["Interfaces", (data.interfaces || []).join(", ") || "Unavailable"], ...(data.batteries || []).map((b) => [b.name, `${b.capacity}% · ${b.status}`])]]
  ];
  for (const [eyebrow, title, rows] of groups) { const card = element("section", "card information-card"), dl = element("dl"); details(dl, rows.length ? rows : [["Status", "Unavailable"]]); card.append(element("div", "eyebrow", eyebrow), element("h2", "", title), dl); $("information-content").append(card); }
}
let refreshing = false, generation = 0;
async function refresh(quiet = false) {
  if (refreshing || state.busy || document.querySelector("dialog[open]")) return;
  refreshing = true; const page = state.page, current = generation;
  $("refresh").disabled = true;
  try {
    if (page === "apps") { await window.folioStore.refresh(); return; }
    if (page === "settings") { await window.folioSettings.refresh(); return; }
    const data = await api(page);
    if (generation !== current) return;
    state[page] = data;
    if (page === "wifi") renderWifi(); else if (page === "proxy") renderProxy(); else if (page === "devices") renderDevices(); else renderInformation(data);
    $("updated").textContent = "Updated " + new Date().toLocaleTimeString([], {hour: "2-digit", minute: "2-digit"});
    if (!quiet) message("");
  } catch (error) {
    if (generation !== current) return;
    state[page] = null;
    if (page === "wifi") renderWifi(); else if (page === "proxy") renderProxy(); else if (page === "devices") renderDevices(); else renderInformation(null);
    message(error.message, true);
  } finally { refreshing = false; $("refresh").disabled = false; if (generation !== current) refresh(); }
}
function renderControls() { renderWifi(); renderProxy(); renderDevices(); }
async function operate(domain, action, fields = {}) {
  if (state.busy) return;
  state.busy = true; generation++; renderControls(); message(action === "connect" ? "Connecting…" : "Applying…");
  let success = false;
  try { await api("action", {domain, action, fields}); success = true; }
  catch (error) { message(error.message, true); }
  finally { delete fields.password; state.busy = false; renderControls(); await refresh(true); }
  if (success) message(action === "connect" ? "Connected." : "Changes applied.");
}
function confirmAction(title, description, callback) {
  const dialog = $("confirm-dialog"); $("confirm-title").textContent = title; $("confirm-description").textContent = description; dialog.returnValue = "";
  dialog.onclose = () => { if (dialog.returnValue === "confirm") callback(); }; dialog.showModal();
}
let connectingHidden = false, connectingNetwork = null;
function openConnect(hidden) {
  connectingHidden = hidden; connectingNetwork = hidden ? null : network(); if (!hidden && !connectingNetwork) return;
  $("dialog-title").textContent = hidden ? "Hidden network" : connectingNetwork.ssid || "Join network";
  $("dialog-description").textContent = hidden ? "Enter the network name and its security type." : connectingNetwork.security;
  $("hidden-fields").hidden = !hidden; $("ssid").value = ""; $("ssid").required = hidden;
  $("password").value = ""; $("password").type = "password"; $("show-password").checked = false; $("connect-dialog").showModal();
}
$("connect-dialog").addEventListener("close", () => { $("password").value = ""; $("password").type = "password"; connectingNetwork = null; });
$("connect-form").onsubmit = (event) => {
  event.preventDefault(); const fields = {interface: $("adapter").value, password: $("password").value};
  if (connectingHidden) Object.assign(fields, {hidden: true, ssid: $("ssid").value, security: $("security").value});
  else { fields.ap = connectingNetwork.path; if (connectingNetwork.profiles?.length) fields.uuid = connectingNetwork.profiles[0]; }
  $("password").value = ""; $("connect-dialog").close(); operate("wifi", "connect", fields);
};
$("show-password").onchange = () => { $("password").type = $("show-password").checked ? "text" : "password"; };
$("cancel-connect").onclick = () => $("connect-dialog").close();
$("connect").onclick = () => openConnect(false); $("hidden-network").onclick = () => openConnect(true);
$("adapter").onchange = renderWifi; $("backlight").onchange = renderBacklight;
$("scan").onclick = () => operate("wifi", "scan", {interface: $("adapter").value});
$("radio").onclick = () => { const enabled = !state.wifi.enabled; confirmAction(enabled ? "Turn on Wi-Fi?" : "Turn off Wi-Fi?", enabled ? "Enable wireless connections." : "Your active wireless connection will be interrupted.", () => operate("wifi", "radio", {enabled})); };
$("disconnect").onclick = () => { const fields = {interface: $("adapter").value}; confirmAction("Disconnect Wi-Fi?", "Your active wireless connection will be interrupted.", () => operate("wifi", "disconnect", fields)); };
$("forget").onclick = () => { const n = network(), fields = {interface: $("adapter").value, uuid: n.profiles[0]}; confirmAction("Forget " + n.ssid + "?", "The saved connection will be removed. An active connection may be affected.", () => operate("wifi", "forget", fields)); };
$("mode").onchange = () => operate("proxy", "proxy-mode", {mode: $("mode").value});
$("mute").onclick = () => operate("devices", "mute"); $("set-output").onclick = () => operate("devices", "output", {name: $("output").value});
for (const [id, action] of [["volume", "volume"], ["brightness", "brightness"]]) {
  $(id).oninput = () => { $(id + "-value").textContent = $(id).value + "%"; };
  $(id).onchange = () => operate("devices", action, {level: Number($(id).value), ...(id === "brightness" ? {device: $("backlight").value} : {})});
}
async function testNodes(nodes) {
  if (state.testing) { state.stopTesting = true; renderProxy(); return; }
  state.testing = true; state.stopTesting = false;
  try {
    for (const node of nodes) {
      if (state.stopTesting) break;
      state.delays.set(node, "Testing…"); renderProxy();
      try { const data = await api("action", {domain: "proxy", action: "proxy-delay", fields: {node}}); state.delays.set(node, data.delay + " ms"); }
      catch { state.delays.set(node, "Timed out or unavailable"); }
      renderProxy();
    }
  } finally { state.testing = false; state.stopTesting = false; renderProxy(); }
}
$("test-all").onclick = () => testNodes(proxyNodes().map(n => n.name));
$("refresh").onclick = () => refresh();
for (const button of document.querySelectorAll("[data-page]")) button.onclick = () => {
  state.page = button.dataset.page; generation++;
  for (const page of document.querySelectorAll(".page")) page.hidden = page.id !== state.page;
  for (const nav of document.querySelectorAll(".nav")) { nav.classList.toggle("active", nav === button); nav.setAttribute("aria-current", nav === button ? "page" : "false"); }
  $("page-title").textContent = descriptions[state.page][0]; $("page-description").textContent = descriptions[state.page][1]; message(""); refresh();
};
setInterval(() => { if (!document.hidden && !state.testing && !document.activeElement?.matches("input,select,.network-row,.node-actions button")) refresh(true); }, 8000);
if (token) refresh(); else { renderControls(); message("Open this panel with folio panel to connect to your computer.", true); }
