# Drives the live page in headless Chromium: WebRTC video must play, the dog must be
# detected, and the visit must land in "Latest visits" as a recording.
import sys, time
from playwright.sync_api import sync_playwright

url = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:4000/"
with sync_playwright() as p:
    b = p.chromium.launch(args=["--autoplay-policy=no-user-gesture-required"])
    page = b.new_page(viewport={"width": 1280, "height": 900})
    page.on("console", lambda m: print("console:", m.text))
    page.goto(url)
    page.wait_for_function("document.querySelector('#live-video video').videoWidth > 0", timeout=20000)
    print("video playing:", page.evaluate("[document.querySelector('#live-video video').videoWidth, document.querySelector('#live-video video').videoHeight]"))
    page.wait_for_selector("text=Dog detected", timeout=30000)
    print("badge: dog detected")
    page.wait_for_function("[...document.querySelectorAll('#live-video div.border-warning')].some(b => !b.hidden)", timeout=10000)
    print("box:", page.evaluate("(() => { const b = [...document.querySelectorAll('#live-video div.border-warning')].find(b => !b.hidden); return b.style.cssText })()"))
    page.screenshot(path="tmp/e2e-live-dog.png")
    page.wait_for_selector("text=Watching", timeout=40000)
    page.wait_for_selector("section img[src^='/thumbs/']", timeout=10000)
    print("recording listed")
    page.screenshot(path="tmp/e2e-live.png")
    page.click("section button.card")
    page.wait_for_selector("#player video", timeout=10000)
    time.sleep(2)
    print("player:", page.evaluate("(() => { const v = document.querySelector('#player video'); return [v.readyState, v.duration] })()"))
    page.screenshot(path="tmp/e2e-player.png")
    b.close()
