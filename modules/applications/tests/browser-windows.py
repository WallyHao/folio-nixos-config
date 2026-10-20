"""Exercise policy installation and native Zen windows in a disposable profile."""

import json
import os
from pathlib import Path
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from selenium import webdriver
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.firefox.service import Service
from selenium.webdriver.support.ui import WebDriverWait


class Page(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        content = b'<!doctype html><title>Folio fixture</title><a id="link" href="/second" target="_blank">Open another page</a><input id="text" value="preserved">'
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)


out = Path(sys.argv[1])
profile = Path(os.environ["HOME"]) / "disposable-profile"
profile.mkdir()
options = Options()
options.binary_location = os.environ["BROWSER"]
options.add_argument("-profile")
options.add_argument(str(profile))
for name, value in {
    "browser.startup.homepage": "about:blank",
    "browser.startup.page": 0,
    "browser.aboutwelcome.enabled": False,
    "zen.welcome-screen.seen": True,
    "zen.welcome-screen.enabled": False,
    "browser.shell.checkDefaultBrowser": False,
    "browser.newtabpage.enabled": False,
    "network.proxy.type": 0,
}.items():
    options.set_preference(name, value)

server = ThreadingHTTPServer(("127.0.0.1", 0), Page)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
driver = None
try:
    driver = webdriver.Firefox(options=options, service=Service(executable_path=os.environ["GECKODRIVER"], service_args=["--allow-system-access"], log_output=str(out / "geckodriver.log")))
    wait = WebDriverWait(driver, 45)

    def chrome(script, *args):
        with driver.context(driver.CONTEXT_CHROME):
            return driver.execute_script(script, *args)

    observed_windows = []

    def windows():
        # Zen keeps an internal empty placeholder; it is not a user tab and its
        # WebExtension ID is TAB_ID_NONE. Count only actual page tabs.
        snapshot = chrome('return Array.from(Services.wm.getEnumerator("navigator:browser")).filter(w=>w.gBrowser).map(w=>({tabs:Array.from(w.gBrowser.tabs).filter(t=>!t.hasAttribute("zen-empty-tab")).length,private:PrivateBrowsingUtils.isWindowPrivate(w)}))')
        if not observed_windows or snapshot != observed_windows[-1]:
            observed_windows.append(snapshot)
            print("Fixture windows:", snapshot, flush=True)
        assert len(snapshot) <= 8, "Runaway window creation"
        return snapshot

    def installed(_driver):
        with driver.context(driver.CONTEXT_CHROME):
            return driver.execute_async_script('const done=arguments[0];ChromeUtils.importESModule("resource://gre/modules/AddonManager.sys.mjs").AddonManager.getAddonByID("onetab@nonexistenturl.net").then(a=>done(a && a.isActive && a.version === "0.2.1"))')

    wait.until(installed)
    wait.until(lambda _d: chrome('const {ExtensionParent}=ChromeUtils.importESModule("resource://gre/modules/ExtensionParent.sys.mjs"); return ExtensionParent.GlobalManager.getExtension("onetab@nonexistenturl.net")?.backgroundState === "running"'))
    policies = chrome("return Services.policies.getActivePolicies()")
    extension = policies["ExtensionSettings"]["onetab@nonexistenturl.net"]
    assert extension["install_url"].startswith("file:///nix/store/")
    assert extension["private_browsing"] and extension["updates_disabled"]
    url = f"http://127.0.0.1:{server.server_port}/"
    driver.get(url)
    chrome('gBrowser.addTab(arguments[0], {triggeringPrincipal:Services.scriptSecurityManager.getSystemPrincipal()})', url)
    wait.until(lambda _d: len(windows()) == 1 and windows()[0]["tabs"] == 1)
    chrome('gBrowser.addTab(arguments[0], {triggeringPrincipal:Services.scriptSecurityManager.getSystemPrincipal()})', url)
    wait.until(lambda _d: len(windows()) == 2 and all(w["tabs"] == 1 for w in windows()))
    driver.switch_to.window(driver.window_handles[-1])
    driver.get(url)
    assert driver.find_element("id", "text").get_attribute("value") == "preserved"
    driver.find_element("id", "link").click()
    wait.until(lambda _d: len(windows()) == 3 and all(w["tabs"] == 1 for w in windows()))
    # Private browsing receives the same managed extension permission.
    chrome("OpenBrowserWindow({private:true})")
    wait.until(lambda _d: sum(w["private"] for w in windows()) == 1)
    wait.until(lambda _d: chrome('return Array.from(Services.wm.getEnumerator("navigator:browser")).find(w=>PrivateBrowsingUtils.isWindowPrivate(w))?.gBrowserInit.delayedStartupFinished'))
    chrome('const w=Array.from(Services.wm.getEnumerator("navigator:browser")).find(w=>PrivateBrowsingUtils.isWindowPrivate(w)); w.gBrowser.addTab(arguments[0], {triggeringPrincipal:Services.scriptSecurityManager.getSystemPrincipal()})', url)
    chrome('const w=Array.from(Services.wm.getEnumerator("navigator:browser")).find(w=>PrivateBrowsingUtils.isWindowPrivate(w)); w.gBrowser.addTab(arguments[0], {triggeringPrincipal:Services.scriptSecurityManager.getSystemPrincipal()})', url)
    wait.until(lambda _d: sum(w["private"] for w in windows()) == 2 and all(w["tabs"] == 1 for w in windows()))
    # Make the old multi-tab session with Zen itself, then restart it. Temporarily
    # disable the extension only in the disposable test profile while seeding.
    original = driver.window_handles[0]
    driver.switch_to.window(original)
    chrome('for (const w of Services.wm.getEnumerator("navigator:browser")) { if (w !== window) w.close(); }')
    with driver.context(driver.CONTEXT_CHROME):
        driver.execute_async_script('const done=arguments[0]; ChromeUtils.importESModule("resource://gre/modules/AddonManager.sys.mjs").AddonManager.getAddonByID("onetab@nonexistenturl.net").then(a=>a.disable()).then(()=>done(true))')
    chrome('for (const suffix of ["restored-a", "restored-b"]) gBrowser.addTab(arguments[0]+suffix, {triggeringPrincipal:Services.scriptSecurityManager.getSystemPrincipal()})', url)
    wait.until(lambda _d: len(windows()) == 1 and windows()[0]["tabs"] == 3)
    with driver.context(driver.CONTEXT_CHROME):
        driver.execute_async_script('''const done=arguments[0];
          const {TabStateFlusher}=ChromeUtils.importESModule("moz-src:///browser/components/sessionstore/TabStateFlusher.sys.mjs");
          TabStateFlusher.flushWindow(window).then(()=>ChromeUtils.importESModule("resource://gre/modules/AddonManager.sys.mjs").AddonManager.getAddonByID("onetab@nonexistenturl.net")).then(a=>a.enable()).then(()=>done(true));''')
    chrome('Services.prefs.setIntPref("browser.startup.page",3); Services.prefs.savePrefFile(null)')
    driver.quit()
    driver = None
    options.set_preference("browser.startup.page", 3)
    options.set_preference("browser.sessionstore.resume_session_once", True)
    with (profile / "user.js").open("a") as preferences:
        preferences.write('\nuser_pref("browser.startup.page", 3);\nuser_pref("browser.sessionstore.resume_session_once", true);\n')
    driver = webdriver.Firefox(options=options, service=Service(executable_path=os.environ["GECKODRIVER"], service_args=["--allow-system-access"], log_output=str(out / "restore-geckodriver.log")))
    wait = WebDriverWait(driver, 45)
    assert chrome('return Services.prefs.getIntPref("browser.startup.page")') == 3
    wait.until(lambda _d: len(windows()) == 3 and all(w["tabs"] == 1 for w in windows()))
    restored = chrome('return Array.from(Services.wm.getEnumerator("navigator:browser")).flatMap(w=>Array.from(w.gBrowser.tabs).filter(t=>!t.hasAttribute("zen-empty-tab")).map(t=>t.linkedBrowser.currentURI.spec))')
    assert sorted(restored) == [url, url + "restored-a", url + "restored-b"], restored
    (out / "result.json").write_text(json.dumps({"extension": "0.2.1", "windows": windows(), "newTab": "passed", "targetBlank": "passed", "privateTab": "passed", "sessionRestore": "passed"}, indent=2) + "\n")
    print("PASS: new tabs, links, private tabs and restored tabs create independent one-tab Zen windows.")
except Exception:
    if driver:
        print("Window diagnostics:", windows(), flush=True)
        print("Browser diagnostics:", chrome('return Services.console.getMessageArray().map(m=>m.message).filter(m=>/onetab|extension|error/i.test(m)).slice(-12)'), flush=True)
    raise
finally:
    if driver:
        driver.quit()
    server.shutdown()
    server.server_close()
    thread.join()
