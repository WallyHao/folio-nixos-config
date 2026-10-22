"""Real browser interactions against the loopback server and deterministic clients."""

import json
import os
import sys
import threading
from pathlib import Path

from playwright.sync_api import sync_playwright, expect

from folio_panel.server import PanelServer
from test_panel import Client, Store

def assert_stacked(locator):
    boxes = locator.evaluate_all("nodes => nodes.map(n => {const r=n.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,bottom:r.bottom}})")
    assert len(boxes) > 1
    for previous, current in zip(boxes, boxes[1:]):
        assert abs(previous["x"] - current["x"]) < 1 and abs(previous["width"] - current["width"]) < 1, boxes
        assert current["y"] >= previous["bottom"], boxes


output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
client = Client()
server = PanelServer(client, Store())
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, args=["--no-sandbox"])
        page = browser.new_page(viewport={"width": 960, "height": 1000}, device_scale_factor=1)
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(server.origin + "/#" + server.token)
        expect(page.locator("#network-name")).to_have_text("Everforest")
        assert page.url == server.origin + "/"
        assert page.locator("#networks img").count() == 0
        page.locator(".network-row").filter(has_text="<img").click()
        page.locator("#connect").click()
        expect(page.locator("#password")).to_have_attribute("type", "password")
        page.locator("#password").fill("fixture-secret-only")
        page.locator("#show-password").check()
        expect(page.locator("#password")).to_have_attribute("type", "text")
        page.locator("#connect-form button[type=submit]").click()
        expect(page.locator("#connect-dialog")).not_to_be_visible()
        expect(page.locator("#notice")).to_have_text("Connected.")
        assert any(action == "connect" and fields.get("password") == "fixture-secret-only" for _, action, fields in client.calls)
        assert page.locator("#password").input_value() == ""
        assert "fixture-secret-only" not in page.locator("body").inner_text()
        page.locator("#radio").click()
        page.locator("#confirm-dialog button[value=cancel]").click()
        assert not any(action == "radio" for _, action, _ in client.calls)
        page.locator("#hidden-network").click()
        page.locator("#ssid").fill("Hidden studio")
        page.locator("#security").select_option("Open")
        page.locator("#connect-form button[type=submit]").click()
        expect(page.locator("#notice")).to_have_text("Connected.")
        assert any(fields.get("hidden") and fields.get("ssid") == "Hidden studio" for _, _, fields in client.calls)

        page.locator('[data-page="proxy"]').click()
        expect(page.locator("#nodes .node-row")).to_have_count(4)
        page.locator("#mode").select_option("direct")
        expect(page.locator("#notice")).to_have_text("Changes applied.")
        assert ("proxy", "proxy-mode", {"mode": "direct"}) in client.calls
        page.locator("#nodes .node-row").filter(has_text="Tokyo").get_by_role("button", name="Test", exact=True).click()
        expect(page.locator("#nodes .node-row").filter(has_text="Tokyo")).to_contain_text("24 ms")
        assert not any(action == "proxy-group-select" for _, action, _ in client.calls)
        page.locator("#mode").select_option("global")
        expect(page.locator("#notice")).to_have_text("Changes applied.")
        page.locator("#nodes .node-row").filter(has_text="Tokyo").get_by_role("button", name="Use", exact=True).click()
        expect(page.locator("#notice")).to_have_text("Node selected.")
        expect(page.locator("#nodes .node-row").filter(has_text="Tokyo").get_by_role("button", name="Selected", exact=True)).to_be_disabled()
        assert ("proxy", "proxy-group-select", {"group": "GLOBAL", "node": "PROXY"}) in client.calls
        assert any(action == "proxy-group-select" and fields["node"] == "Tokyo · 02" for _, action, fields in client.calls)
        page.locator("#test-all").click()
        expect(page.locator("#test-all")).to_have_text("Test all")
        expect(page.locator("#nodes .row-end")).to_have_text(["24 ms"] * 4)
        page.screenshot(path=str(output / "proxy.png"), full_page=True)

        page.locator('[data-page="devices"]').click()
        expect(page.locator("#volume")).to_be_enabled()
        page.locator("#volume").fill("55")
        page.locator("#volume").dispatch_event("change")
        expect(page.locator("#notice")).to_have_text("Changes applied.")
        assert ("devices", "volume", {"level": 55}) in client.calls
        page.locator("#brightness").fill("72")
        page.locator("#brightness").dispatch_event("change")
        expect(page.locator("#notice")).to_have_text("Changes applied.")
        assert ("devices", "brightness", {"level": 72, "device": "intel_backlight"}) in client.calls
        page.locator("#output").select_option("headphones")
        page.locator("#set-output").click()
        expect(page.locator("#notice")).to_have_text("Changes applied.")
        assert ("devices", "output", {"name": "headphones"}) in client.calls
        page.locator("#mute").click()
        expect(page.locator("#notice")).to_have_text("Changes applied.")
        assert ("devices", "mute", {}) in client.calls
        page.screenshot(path=str(output / "devices.png"), full_page=True)
        page.locator('[data-page="settings"]').click()
        expect(page.locator("#setting-font-size")).to_have_value("16")
        page.locator("#setting-font-size").fill("18")
        page.locator("#settings-form").get_by_role("button", name="Save settings").click()
        expect(page.locator("#notice")).to_contain_text("Settings saved")
        page.locator("#inherit-appearance").check()
        expect(page.locator("#setting-appearance")).to_be_disabled()
        page.screenshot(path=str(output / "settings.png"), full_page=True)
        page.locator('[data-page="health"]').click()
        expect(page.locator("#health-findings")).to_contain_text("folio plan")
        page.screenshot(path=str(output / "diagnostics.png"), full_page=True)
        page.locator('[data-page="devices"]').click()
        client.fail = True
        page.locator("#refresh").click()
        expect(page.locator("#volume")).to_be_disabled()
        expect(page.locator("#brightness")).to_be_disabled()
        expect(page.locator("#mute")).to_be_disabled()
        client.fail = False
        page.locator('[data-page="information"]').click()
        expect(page.locator("#information-content")).to_contain_text("AMD Ryzen 7 9700X")
        page.screenshot(path=str(output / "information.png"), full_page=True)

        client.wireless["adapters"][0]["networks"].pop()
        page.locator('[data-page="wifi"]').click()
        expect(page.locator(".network-row")).to_have_count(2)
        # Half-width tiling is the primary layout, including selected navigation.
        for width in (640, 720, 880, 960, 1200, 1280):
            page.set_viewport_size({"width": width, "height": 1000})
            geometry = page.locator(".nav").evaluate_all("nodes => nodes.map(n => {const r=n.getBoundingClientRect();return [r.x,r.y,r.width,r.height]})")
            assert len({box[1] for box in geometry}) == 1, (width, "Tiled windows must use top navigation")
            for target in ("proxy", "devices", "information", "wifi"):
                page.locator(f'[data-page="{target}"]').click()
                expect(page.locator(f"#{target}")).to_be_visible()
                if target in ("devices", "information"):
                    assert_stacked(page.locator(f"#{target} .card"))
                assert page.evaluate("document.documentElement.scrollWidth <= innerWidth"), (width, target, "horizontal overflow")
                assert page.locator(".nav").evaluate_all("nodes => nodes.every(n => {const r=n.getBoundingClientRect(),p=n.parentElement.getBoundingClientRect(),l=n.querySelector('.nav-label').getBoundingClientRect();return r.left>=p.left-1 && r.right<=p.right+1 && l.left>=r.left-1 && l.right<=r.right+1})"), (width, target, "navigation overflow")
                assert geometry == page.locator(".nav").evaluate_all("nodes => nodes.map(n => {const r=n.getBoundingClientRect();return [r.x,r.y,r.width,r.height]})"), (width, target, "selection moves navigation")
            if width in (720, 960, 1200):
                page.screenshot(path=str(output / f"tiled-{width}.png"), full_page=True)
        page.set_viewport_size({"width": 960, "height": 1000})
        page.locator('[data-page="proxy"]').click()
        expect(page.locator("#nodes .node-row")).to_have_count(4)
        page.screenshot(path=str(output / "tiled-proxy.png"), full_page=True)
        page.locator('[data-page="devices"]').click()
        expect(page.locator("#volume")).to_be_enabled()
        page.screenshot(path=str(output / "tiled-devices.png"), full_page=True)
        page.locator('[data-page="wifi"]').click()
        expect(page.locator(".network-row")).to_have_count(2)
        page.set_viewport_size({"width": 1920, "height": 1000})
        assert page.locator(".nav").evaluate_all("nodes => nodes.every(n => n.getBoundingClientRect().right <= n.parentElement.getBoundingClientRect().right + 1)"), "Wide sidebar overflow"
        page.screenshot(path=str(output / "desktop.png"), full_page=True)
        page.set_viewport_size({"width": 390, "height": 844})
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth"), "Mobile layout overflows"
        page.screenshot(path=str(output / "mobile.png"), full_page=True)
        client.wireless["adapters"] = []
        page.locator("#refresh").click()
        expect(page.locator("#wifi-status")).to_have_text("No Wi-Fi adapter")
        expect(page.locator("#connect")).to_be_disabled()
        page.reload()
        expect(page.locator("#wifi-status")).to_have_text("No Wi-Fi adapter")
        theme = Path(os.environ["XDG_CONFIG_HOME"]) / "folio/appearance.json"
        theme.parent.mkdir(parents=True, exist_ok=True)
        theme.write_text(json.dumps({"appearance": "light", "font-family": "Maple Mono NF CN", "font-size": 16}))
        client.wireless = Client().wireless
        client.wireless["adapters"][0]["networks"].pop()
        page.set_viewport_size({"width": 1440, "height": 1000})
        page.reload()
        expect(page.locator(".network-row")).to_have_count(2)
        assert page.locator("body").evaluate("el => getComputedStyle(el).backgroundColor") == "rgb(255, 251, 239)"
        assert "Maple Mono NF CN" in page.locator("body").evaluate("el => getComputedStyle(el).fontFamily")
        page.screenshot(path=str(output / "light.png"), full_page=True)
        theme.write_text(json.dumps({"appearance": "light", "font-family": "Maple Mono NF CN", "font-size": 24}))
        page.set_viewport_size({"width": 720, "height": 1000})
        page.reload()
        expect(page.locator(".network-row")).to_have_count(2)
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth"), "Large-font tiled layout overflow"
        assert page.locator(".nav").evaluate_all("nodes => nodes.every(n => n.getBoundingClientRect().right <= n.parentElement.getBoundingClientRect().right + 1)"), "Large-font navigation overflow"
        for width in (390, 960, 1920):
            page.set_viewport_size({"width": width, "height": 1000})
            for target in ("devices", "information"):
                page.locator(f'[data-page="{target}"]').click()
                expect(page.locator(f"#{target} .card").first).to_be_visible()
                assert_stacked(page.locator(f"#{target} .card"))
                assert page.evaluate("document.documentElement.scrollWidth <= innerWidth"), (width, target)
                page.screenshot(path=str(output / f"stacked-{target}-{width}.png"), full_page=True)
        # Store interaction crosses the authenticated HTTP and task boundaries.
        theme.write_text(json.dumps({"appearance": "dark", "font-family": "Maple Mono NF CN", "font-size": 16}))
        page.reload()
        page.locator('[data-page="apps"]').click()
        expect(page.locator("#apps")).to_be_visible()
        page.locator("#query").fill("Steam")
        page.locator("#search-button").click()
        expect(page.locator("#results .app-card")).to_have_count(1)
        assert page.locator("#results script").count() == 0
        page.locator("#results").get_by_role("button", name="Install", exact=True).click()
        expect(page.locator("#task-phase")).to_have_text("Completed")
        page.locator("#refresh").click()
        expect(page.locator("#results").get_by_role("button", name="Installed", exact=True)).to_be_disabled()
        page.locator("#installed-tab").click()
        expect(page.locator("#installed-apps .app-card")).to_have_count(1)
        page.locator("#installed-apps").get_by_role("button", name="Uninstall", exact=True).click()
        page.locator("#confirm-dialog button[value=cancel]").click()
        assert server.store.applications
        page.locator("#installed-apps").get_by_role("button", name="Uninstall", exact=True).click()
        page.locator("#confirm-dialog button[value=confirm]").click()
        expect(page.locator("#task-title")).to_have_text("Uninstall application")
        page.locator("#refresh").click()
        expect(page.locator("#installed-apps .app-card")).to_have_count(0)
        page.locator("#discover-tab").click()
        # More than one result catches a return to side-by-side app cards.
        original_search = server.store.search
        server.store.search = lambda query: {"applications": [
            *original_search(query)["applications"],
            {"id": "com.valvesoftware.SteamLink", "name": "Steam Link", "description": "Stream games", "version": "1.0", "branch": "stable", "remote": "flathub"},
        ]}
        page.locator("#search-button").click()
        expect(page.locator("#results .app-card")).to_have_count(2)
        assert page.locator(".feature, #find-steam").count() == 0
        for width in (390, 720, 960, 1920):
            page.set_viewport_size({"width": width, "height": 1000})
            assert_stacked(page.locator("#results .app-card"))
            assert page.locator("#results .app-actions button").evaluate_all("nodes => new Set(nodes.map(n => {const r=n.getBoundingClientRect();return `${r.width}:${r.height}`})).size === 1"), "App actions must have matching dimensions"
            assert page.locator(".store-tabs button").evaluate_all("nodes => new Set(nodes.map(n => {const r=n.getBoundingClientRect();return `${r.width}:${r.height}`})).size === 1"), "Store tabs must have matching dimensions"
            assert page.evaluate("document.documentElement.scrollWidth <= innerWidth"), (width, "Store overflow")
            page.screenshot(path=str(output / f"store-{width}.png"), full_page=True)
        page.reload()
        page.locator('[data-page="apps"]').click()
        expect(page.locator("#task-title")).to_have_text("Uninstall application")
        assert not errors, errors
        browser.close()
        print("PASS: Wi-Fi secrets/hidden networks/confirmation, proxy/mode/latency, volume/backlight, stale controls, device information, token reload and mobile layout.")
finally:
    server.shutdown()
    server.server_close()
    thread.join()
