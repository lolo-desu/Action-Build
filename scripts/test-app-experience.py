"""Verify glass integration against a local, non-account browser fixture."""
from pathlib import Path
import os
from playwright.sync_api import sync_playwright

root=Path(__file__).resolve().parents[1]
fixture=(root/'scripts/layout-fixture.html').read_text()
with sync_playwright() as p:
    browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH','/usr/bin/chromium'),args=['--no-sandbox'])
    baseline=browser.new_page(viewport={'width':393,'height':793},is_mobile=True,has_touch=True)
    baseline.route('https://erp.sex/**',lambda r:r.fulfill(body=fixture,content_type='text/html'))
    baseline.goto('https://erp.sex/discover')
    page=browser.new_page(viewport={'width':393,'height':793},is_mobile=True,has_touch=True)
    page.add_init_script("""window.nativeMessages=[];
    window.webkit={messageHandlers:{erpNativeApp:{postMessage:v=>window.nativeMessages.push(v)}}};
    window.fetch=function(url,options){window.lastFixturePromise=Promise.resolve(new Response('{}',{status:String(url).includes('denied')?403:200}));return window.lastFixturePromise};""")
    page.add_init_script((root/'ERPStable/app-experience.js').read_text())
    page.route('https://erp.sex/**',lambda r:r.fulfill(body=fixture,content_type='text/html'))
    page.goto('https://erp.sex/discover')
    page.wait_for_function("nativeMessages.some(m=>m.kind==='navigation'&&m.items?.length===5)")
    metrics="""() => [...document.querySelectorAll('.app-bottom a,.app-bottom svg')].map(e=>{const r=e.getBoundingClientRect(),c=getComputedStyle(e);return [r.x,r.y,r.width,r.height,c.fontSize,c.color,c.padding]})"""
    assert baseline.evaluate(metrics)==page.evaluate(metrics),'button geometry, fonts or foreground palette changed'
    model=page.evaluate("nativeMessages.filter(m=>m.kind==='navigation').at(-1)")
    assert [i['title'] for i in model['items']]==['探索','喜欢','配对','广场','我的']
    assert [i['path'] for i in model['items']]==['/discover','/likes','/matches','/posts','/me']
    assert model['items'][0]['selected'] and model['items'][1]['badge']['title']=='3'
    assert all(i['icon'].startswith('iVBOR') for i in model['items']),'original SVG icons did not rasterize'
    page.evaluate('__vrcrpNativeNavReady()')
    assert page.locator('.app-bottom').get_attribute('aria-hidden')=='true'
    assert page.locator('.app-bottom').evaluate('e=>getComputedStyle(e).opacity')=='0'
    assert baseline.evaluate(metrics)==page.evaluate(metrics),'native acknowledgement altered navigation layout'
    page.evaluate("""window.originalHitTest=document.elementFromPoint.bind(document);
    document.elementFromPoint=()=>null;window.dispatchEvent(new Event('resize'))""")
    page.wait_for_timeout(100)
    assert page.evaluate("nativeMessages.filter(m=>m.kind==='navigation').at(-1).visible"),'a stale keyboard viewport hid native navigation'
    page.evaluate('__vrcrpActivateTab(3)')
    page.wait_for_function("location.pathname==='/posts'&&nativeMessages.filter(m=>m.kind==='navigation').at(-1).items[3].selected")
    assert page.evaluate('__fixtureClicks')==1,'native tab did not use the original click handler exactly once'
    page.evaluate("history.pushState({idx:history.state.idx+1,key:'detail'},'', '/posts/test')")
    page.wait_for_function("nativeMessages.filter(m=>m.kind==='route').at(-1).canGoBack && nativeMessages.filter(m=>m.kind==='navigation').at(-1).visible===false")
    assert page.locator('.app-bottom').evaluate('e=>getComputedStyle(e).visibility')=='hidden'
    assert not page.evaluate("nativeMessages.filter(m=>m.kind==='navigation').at(-1).overlay"),'detail hiding must not disable native back'
    page.evaluate('__vrcrpBack()')
    page.wait_for_function("location.pathname==='/posts'&&!nativeMessages.filter(m=>m.kind==='route').at(-1).canGoBack")
    page.evaluate("const modal=document.createElement('div');modal.id='test-modal';modal.setAttribute('role','dialog');modal.style='position:fixed;inset:0;z-index:999;background:white';document.body.appendChild(modal)")
    page.wait_for_function("nativeMessages.filter(m=>m.kind==='navigation').at(-1).visible===false")
    page.evaluate("document.getElementById('test-modal').remove()")
    page.wait_for_function("nativeMessages.filter(m=>m.kind==='navigation').at(-1).visible===true")
    page.evaluate("void(document.elementFromPoint=originalHitTest)")
    page.evaluate("const backdrop=document.createElement('div');backdrop.id='test-backdrop';backdrop.style='position:fixed;inset:0;z-index:101;background:rgba(0,0,0,.2)';document.body.appendChild(backdrop)")
    page.wait_for_function("nativeMessages.filter(m=>m.kind==='navigation').at(-1).visible===false")
    page.evaluate("document.getElementById('test-backdrop').remove()")
    page.wait_for_function("nativeMessages.filter(m=>m.kind==='navigation').at(-1).visible===true")
    page.evaluate("__vrcrpActivateTab(0)")
    page.wait_for_function("location.pathname==='/discover'&&!nativeMessages.filter(m=>m.kind==='route').at(-1).canGoBack")
    page.evaluate("history.pushState({},'', '/matches/denied')")
    page.wait_for_function("nativeMessages.filter(m=>m.kind==='route').at(-1).path==='/matches/denied'")
    before=page.evaluate("nativeMessages.filter(m=>m.kind==='haptic').length")
    assert page.evaluate("(() => {const p=fetch('/api/v1/matches/test/messages',{method:'POST',body:'private-text'});return p===lastFixturePromise})()")
    page.wait_for_function("nativeMessages.some(m=>m.kind==='haptic'&&m.style==='success')")
    page.evaluate("fetch('/api/v1/matches/denied/messages',{method:'POST'})")
    page.wait_for_timeout(100)
    assert page.evaluate("nativeMessages.filter(m=>m.kind==='haptic').length")==before+1,'failed sends must not provide success feedback'
    assert not page.evaluate("JSON.stringify(nativeMessages).includes('private-text')"),'message bodies crossed the bridge'
    page.evaluate("__vrcrpAccessibility({reduceTransparency:true,reduceMotion:true})")
    assert page.locator('.app-top').evaluate('e=>getComputedStyle(e).backdropFilter')=='none'
    baseline.close();browser.close()
print('PASS: original button geometry/colors/icons, native tab actions, badges, detail back, card gesture exclusion, modal avoidance, send feedback and accessibility')
