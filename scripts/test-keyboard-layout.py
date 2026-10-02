"""Browser acceptance checks for the chat layout under native viewport changes.

Requires Playwright for Python and a Chromium executable. This checks the web
layout; actual iOS keyboard geometry still needs verification on a device.
"""
from pathlib import Path
from playwright.sync_api import sync_playwright
import os

root = Path(__file__).resolve().parents[1]
fixture = """<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
* {box-sizing:border-box} html,body {margin:0} body{font-family:sans-serif}
.h-dvh{height:100dvh}.shell{display:flex;flex-direction:column}
.app-top{flex-shrink:0;height:65px;padding:12px}
main{display:flex;flex-direction:column;flex:1;min-height:0;padding:16px 12px 76px}
.chat{display:flex;flex-direction:column;flex:1;min-height:0;gap:12px}
.chat-header{height:50px;flex-shrink:0}
.messages{flex:1;min-height:0;overflow:auto;border:1px solid}
.composer{flex-shrink:0;display:flex;padding:12px;border:1px solid}
textarea{flex:1;min-width:0;height:44px;font-size:14px} .local-note{font-size:11px;flex-shrink:0}
.app-bottom{position:fixed;left:0;right:0;bottom:0;height:64px;border-top:1px solid}
</style></head><body><div class="shell h-dvh"><header class="app-top">Site navigation</header>
<main id="main"><section class="chat"><header class="chat-header">Chat</header>
<div class="messages"><div style="height:900px">Older messages</div><p data-last-message>Latest message</p></div><form class="composer"><textarea aria-label="Message"></textarea><button>Send</button></form>
<div class="local-note">Chat history saved locally</div></section></main></div>
<nav class="app-bottom">Tabs</nav></body></html>"""

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=os.environ.get("CHROMIUM_PATH", "/usr/bin/chromium"), args=["--no-sandbox"])
    page = browser.new_page(viewport={"width": 393, "height": 793}, is_mobile=True, has_touch=True)
    page.add_init_script((root / "ERPStable/interaction.js").read_text())
    page.add_init_script((root / "ERPStable/keyboard.js").read_text())
    page.route("https://erp.sex/**", lambda route: route.fulfill(body=fixture, content_type="text/html"))
    page.goto("https://erp.sex/matches/test")
    page.evaluate("window.__vrcrpSetViewport({width:393,height:793,keyboardVisible:false})")
    page.wait_for_function("document.documentElement.dataset.vrcrpViewport === 'true'")
    # Native patches must not change the site's fonts, paddings or button layout.
    baseline = browser.new_page(viewport={"width":393,"height":793},is_mobile=True,has_touch=True)
    baseline.route("https://erp.sex/**",lambda route:route.fulfill(body=fixture,content_type="text/html"))
    baseline.goto("https://erp.sex/matches/test")
    measure = """() => ['.app-top','.app-bottom','textarea','button','.composer','main'].map(s => {
        const e=document.querySelector(s),r=e.getBoundingClientRect(),c=getComputedStyle(e);
        return [s,r.x,r.y,r.width,r.height,c.fontSize,c.padding,c.borderRadius,c.backgroundColor];
    })"""
    assert baseline.evaluate(measure) == page.evaluate(measure), "website appearance changed"
    assert page.locator('textarea').evaluate("e => getComputedStyle(e).userSelect") == 'text'
    baseline.close()
    page.locator(".messages").evaluate("e=>{e.scrollTop=e.scrollHeight;e.dispatchEvent(new Event('scroll'))}")
    page.locator("textarea").focus()
    # WebKit can scroll the pane during focus before native keyboard geometry.
    page.locator('.messages').evaluate("e=>{e.scrollTop-=300;e.dispatchEvent(new Event('scroll'))}")
    assert page.locator('.messages').evaluate('e=>e.scrollHeight-e.scrollTop-e.clientHeight')<2
    page.evaluate('__vrcrpWillResizeViewport()')
    for height in [434, 793, 402, 440, 793, 434]:
        page.set_viewport_size({"width": 393, "height": height})
        page.evaluate("v => window.__vrcrpSetViewport(v)", {"width": 393, "height": height, "keyboardVisible": height < 793})
        page.wait_for_function("h => getComputedStyle(document.querySelector('.h-dvh')).height === h + 'px'", arg=height)
        metrics = page.evaluate("""() => {
            const box = document.querySelector('textarea').getBoundingClientRect();
            const nav = document.querySelector('.app-bottom').getBoundingClientRect();
            const pane=document.querySelector('.messages');return {top:box.top,bottom:box.bottom,navTop:nav.top,scroll:document.documentElement.scrollHeight,gap:pane.scrollHeight-pane.scrollTop-pane.clientHeight,last:document.querySelector('[data-last-message]').getBoundingClientRect().bottom,paneBottom:pane.getBoundingClientRect().bottom};
        }""")
        assert metrics["top"] >= 0 and metrics["bottom"] <= metrics["navTop"], metrics
        assert metrics["scroll"] <= height, metrics
        assert metrics["gap"]<2 and metrics["last"]<=metrics["paneBottom"]+1,metrics
        page.evaluate('__vrcrpDidResizeViewport()')
        page.evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>requestAnimationFrame(resolve))))')
    # Browsing older messages must preserve its position when the pane resizes.
    page.locator('.messages').evaluate("e=>{e.scrollTop=120;e.dispatchEvent(new Event('scroll'))}")
    page.evaluate('__vrcrpSetViewport({width:393,height:420,keyboardVisible:true})')
    assert page.locator('.messages').evaluate('e=>e.scrollTop')==120
    page.evaluate('__vrcrpSetViewport({width:393,height:434,keyboardVisible:true})')
    assert page.locator('.messages').evaluate('e=>e.scrollTop')==120
    page.locator('.messages').evaluate("e=>{e.scrollTop=e.scrollHeight;e.dispatchEvent(new Event('scroll'))}")
    page.locator("textarea").evaluate("el => el.style.height='100px'")
    metrics = page.evaluate("""() => ({bottom:document.querySelector('textarea').getBoundingClientRect().bottom,
        navTop:document.querySelector('.app-bottom').getBoundingClientRect().top})""")
    assert metrics["bottom"] <= metrics["navTop"], metrics
    # The CSS height must follow native geometry even when dvh is stale.
    page.add_style_tag(content=".h-dvh {height:793px}")
    assert page.locator(".h-dvh").evaluate("el => Math.round(el.getBoundingClientRect().height)") == 434
    # Invalid updates cannot collapse the page.
    page.evaluate("window.__vrcrpSetViewport({width:393,height:0,keyboardVisible:true})")
    assert page.locator(".h-dvh").evaluate("el => Math.round(el.getBoundingClientRect().height)") == 434
    # Keyboard updates must apply even while paint frames are paused.
    page.evaluate("window.fixtureRAF=requestAnimationFrame;window.requestAnimationFrame=()=>0;__vrcrpSetViewport({width:393,height:420,keyboardVisible:true})")
    assert page.locator('.h-dvh').evaluate("e=>e.getBoundingClientRect().height")==420,'native height waited for requestAnimationFrame'
    page.evaluate("__vrcrpSetViewport({width:393,height:434,keyboardVisible:true});void(window.requestAnimationFrame=fixtureRAF)")
    # Leaving chat restores normal document scrolling for long forms.
    page.evaluate("history.pushState({},'', '/settings'); document.body.appendChild(document.createElement('div'))")
    page.wait_for_function("document.documentElement.dataset.vrcrpChat === 'false'")
    assert page.locator("body").evaluate("el => getComputedStyle(el).overflow") != "hidden"
    assert page.locator('.h-dvh').evaluate("e => e.getBoundingClientRect().height") == 793, "non-chat layout must retain its original height rules"
    browser.close()
print("PASS: original fonts/layout, first keyboard presentation, hide/reopen, height changes, latest message and reader position, multiline composer, stale dvh and paused paint frames, invalid viewport and unchanged non-chat layout")
