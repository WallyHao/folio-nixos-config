"use strict";
(() => {
  let current = null, dirty = false, loading = false;
  const fields = ["font-family", "font-size"];
  function render() {
    if (!current) return;
    $("system-theme").textContent = current.effective.scheme + "-" + current.effective.appearance;
    const deployment = current.deployment || {};
    $("settings-deployment").textContent = deployment.recoveryRequired ? "Configuration persistence or deployment requires recovery. Open Diagnostics for the next step." :
      deployment.pending === true ? "Saved settings await deployment. Run folio plan to review the changes." :
      deployment.pending === false ? "Saved configuration matches the recorded deployment. Some changes may still require reopening an application or starting a new session." :
      "Deployment state is unavailable. Open Diagnostics to inspect the services.";
    for (const key of fields) {
      $("setting-" + key).value = current.effective[key];
      $("inherit-" + key).checked = !(key in current.preferences);
      $("setting-" + key).disabled = $("inherit-" + key).checked;
      $("origin-" + key).textContent = current.origins[key];
    }
    $("save-settings").disabled = false;
  }
  async function refresh() {
    if (loading) return;
    loading = true;
    try {
      if (state.page === "settings" && !dirty) { current = await api("settings"); render(); }
      if (state.page === "health") {
        const report = await api("doctor");
        $("health-state").textContent = report.health;
        const container = $("health-findings"); container.replaceChildren();
        for (const finding of report.findings) {
          const card = element("article", "card");
          card.append(element("h2", "", finding.scope), element("p", "", finding.message), element("code", "", finding.nextCommand));
          container.append(card);
        }
        if (!report.findings.length) container.append(element("p", "", "Both configuration scopes are current. No deployment recovery is pending."));
      }
    } catch (error) { message(error.message, true); }
    finally { loading = false; }
  }
  for (const key of fields) {
    $("setting-" + key).oninput = () => { dirty = true; };
    $("inherit-" + key).onchange = () => {
      dirty = true; $("setting-" + key).disabled = $("inherit-" + key).checked;
      if ($("inherit-" + key).checked && current) $("setting-" + key).value = current.defaults[key];
      $("origin-" + key).textContent = $("inherit-" + key).checked ? "system default" : "user override";
    };
  }
  $("reload-settings").onclick = () => {
    if (dirty) confirmAction("Discard unsaved settings?", "Reload current settings and discard this draft?", () => { dirty = false; refresh(); });
    else refresh();
  };
  $("settings-form").onsubmit = async event => {
    event.preventDefault(); if (!current) return;
    const preferences = {};
    for (const key of fields) preferences[key] = $("inherit-" + key).checked ? null : key === "font-size" ? Number($("setting-" + key).value) : $("setting-" + key).value;
    $("save-settings").disabled = true;
    try {
      await api("settings", {digest: current.digest, preferences});
      dirty = false; await refresh(); message("Settings saved. Run folio plan, then build and apply the reviewed plan to activate them.");
    } catch (error) { message(error.message, true); }
    finally { $("save-settings").disabled = false; }
  };
  window.folioSettings = {refresh};
})();
