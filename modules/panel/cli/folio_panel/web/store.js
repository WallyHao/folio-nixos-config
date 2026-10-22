"use strict";
(() => {
let current = {applications: [], remotes: [], task: null}, results = [], searching = false, submitting = false, loading = true, searchSequence = 0;
function node(tag, cls, text) { const n = document.createElement(tag); n.className = cls; if (text !== undefined) n.textContent = text; return n; }
function notice(text, error = false) { if (state.page === "apps") message(text, error); }
async function api(path, body) {
  const response = await fetch("/api/apps" + path, {method: body ? "POST" : "GET", headers: {Authorization: "Bearer " + token, ...(body ? {"Content-Type": "application/json"} : {})}, body: body ? JSON.stringify(body) : undefined});
  const reply = await response.json(); if (!response.ok) throw Error(reply.error || "Service unavailable"); return reply.data;
}
const busy = () => loading || submitting || current.task?.phase === "running";
function render() {
  $("setup").hidden = loading || current.remotes.includes("flathub");
  for (const id of ["add-source", "update-catalog"]) $(id).disabled = busy();
  $("search-button").disabled = loading || searching || !current.remotes.length;
  $("installed-title").textContent = `Installed applications · ${current.applications.length}`;
  cards($("installed-apps"), current.applications, true);
  cards($("results"), results, false);
  const task = current.task;
  $("transaction").hidden = !task;
  if (task) {
    $("task-title").textContent = ({setup: "Set up Flathub", refresh: "Update catalogue", install: "Install application", remove: "Uninstall application"}[task.action] || "Application task") + (task.fields.id ? " · " + task.fields.id : "");
    $("task-phase").textContent = {running: "Running…", succeeded: "Completed", failed: "Failed", interrupted: "Interrupted"}[task.phase] || task.phase;
    $("task-progress").hidden = task.phase !== "running";
    $("task-log").textContent = task.detail || task.log || "Waiting for application worker…";
    $("task-error").hidden = !task.error; $("task-error").textContent = task.error || "";
    $("resume-app").hidden = !["failed", "interrupted"].includes(task.phase);
    $("resume-app").disabled = busy();
  }
}
function cards(container, apps, installed) {
  container.replaceChildren();
  if (!apps.length) { container.append(node("p", "empty", loading ? "Loading…" : installed ? "No Flatpak applications installed yet." : "Enter a name to search Flathub.")); return; }
  for (const app of apps) {
    const card = node("article", "card app-card");
    const summary = node("div", "app-summary"), info = node("div", "app-info");
    const avatar = node("span", "app-avatar", Array.from(app.name || app.id)[0].toUpperCase()); avatar.setAttribute("aria-hidden", "true");
    info.append(node("h2", "", app.name || app.id), node("div", "app-id", app.id), node("p", "muted", app.description || app.version || ""));
    summary.append(avatar, info); card.append(summary);
    const actions = node("div", "app-actions");
    const found = installed ? [app] : current.applications.filter(a => a.id === app.id);
    actions.append(node("span", "badge", app.remote + (app.scope === "system" ? " · System" : "")));
    if (installed) actions.append(node("span", "badge", app.scope === "system" ? "System provided" : app.managed ? "Managed by Folio" : "User installed"));
    const button = node("button", found.length ? "subtle" : "primary", found.length ? "Installed" : "Install");
    button.disabled = busy() || !!found.length;
    button.onclick = () => act("install", {id: app.id, remote: app.remote, branch: app.branch});
    actions.append(button);
    if (installed && app.removable) {
      const remove = node("button", "subtle danger", "Uninstall"); remove.disabled = busy();
      remove.onclick = () => confirmAction("Uninstall " + app.name + "?", "App data will be kept. Uninstall this application?", () => act("remove", {ref: app.ref}));
      actions.append(remove);
    }
    if (installed && app.scope === "user" && !app.managed) {
      const adopt = node("button", "subtle", "Manage with Folio"); adopt.disabled = busy();
      adopt.onclick = () => confirmAction("Manage " + app.name + " with Folio?", "Add this application to your saved configuration and explicitly adopt its installed revision.", () => act("adopt", {id: app.id, remote: app.remote, branch: app.ref.split("/").at(-1)}));
      actions.append(adopt);
    }
    card.append(actions); container.append(card);
  }
}
async function refresh() {
  try { current = await api(""); loading = false; render(); }
  catch (error) { loading = true; render(); notice(error.message, true); }
}
async function act(action, fields = {}) {
  submitting = true; render(); notice("");
  try { current.task = await api("/action", {action, fields}); }
  catch (error) { notice(error.message, true); }
  finally { submitting = false; render(); }
}
async function search(query) {
  const sequence = ++searchSequence; searching = true; render(); notice("");
  try { const data = await api("/search?q=" + encodeURIComponent(query)); if (sequence === searchSequence) { results = data.applications; $("results-title").textContent = `Search results · ${results.length}`; if (!results.length) notice("No matching applications. Try another name or update the catalogue."); } }
  catch (error) { if (sequence === searchSequence) notice(error.message, true); }
  finally { if (sequence === searchSequence) { searching = false; render(); } }
}
$("search-form").onsubmit = event => { event.preventDefault(); search($("query").value); };
$("add-source").onclick = () => act("setup");
$("update-catalog").onclick = () => act("refresh");
$("resume-app").onclick = () => confirmAction("Resume application task?", "Retry the recorded operation against its saved configuration. Changed configuration or unresolved effects may require manual recovery.", () => act("resume", {id: current.task.id}));

for (const view of ["discover", "installed"]) $(view + "-tab").onclick = () => {
  for (const name of ["discover", "installed"]) { const selected = name === view; $(name).hidden = !selected; $(name + "-tab").className = selected ? "primary" : "subtle"; $(name + "-tab").setAttribute("aria-pressed", String(selected)); }
};
window.folioStore = {refresh};
(async function poll() { if (state.page === "apps" || current.task?.phase === "running") await refresh(); setTimeout(poll, current.task?.phase === "running" ? 1200 : 10000); })();
})();
