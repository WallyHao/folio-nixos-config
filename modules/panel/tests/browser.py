"""Real browser interactions against the loopback server and deterministic clients."""

import json
import os
import sys
import threading
from pathlib import Path

from playwright.sync_api import sync_playwright, expect

from folio_panel.server import PanelServer
from test_panel import Client

output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
client = Client()
server = PanelServer(client)
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
        page.locator("#set-mode").click()
        expect(page.locator("#notice")).to_have_text("Changes applied.")
        assert ("proxy", "proxy-mode", {"mode": "direct"}) in client.calls
        page.locator("#nodes .node-row").filter(has_text="Tokyo").get_by_role("button", name="Test", exact=True).click()
        expect(page.locator("#nodes .node-row").filter(has_text="Tokyo")).to_contain_text("24 ms")
        assert not any(action == "proxy-group-select" for _, action, _ in client.calls)
        page.locator("#nodes .node-row").filter(has_text="Tokyo").get_by_role("button", name="Use", exact=True).click()
        expect(page.locator("#notice")).to_have_text("Changes applied.")
        assert any(action == "proxy-group-select" and fields["node"] == "Tokyo · 02" for _, action, fields in client.calls)
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
        assert not errors, errors
        browser.close()
        print("PASS: Wi-Fi secrets/hidden networks/confirmation, proxy/mode/latency, volume/backlight, stale controls, device information, token reload and mobile layout.")
finally:
    server.shutdown()
    server.server_close()
    thread.join()
