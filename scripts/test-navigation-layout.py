from pathlib import Path
import os
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[1]
fixture=(root/'scripts/navigation-fixture.html').read_text()
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH','/usr/bin/chromium'),args=['--no-sandbox'])
 page=browser.new_page(viewport={'width':393,'height':793},is_mobile=True,has_touch=True)
 page.add_init_script("window.nativeMessages=[];window.webkit={messageHandlers:{erpNativeApp:{postMessage:v=>nativeMessages.push(v)}}}")
 page.add_init_script((root/'ERPStable/keyboard.js').read_text());page.add_init_script((root/'ERPStable/app-experience.js').read_text())
 page.route('https://erp.sex/**',lambda r:r.fulfill(body=fixture,content_type='text/html'));page.goto('https://erp.sex/discover')
 for width,height in [(393,793),(320,568),(393,650),(393,793)]:
  page.set_viewport_size({'width':width,'height':height});page.evaluate('v=>__vrcrpSetViewport(v)',{'width':width,'height':height,'keyboardVisible':False})
  page.wait_for_function("nativeMessages.filter(m=>m.kind==='navigation').at(-1)?.visible")
  page.wait_for_timeout(120);page.evaluate('scrollTo(0,document.documentElement.scrollHeight)');page.wait_for_timeout(50)
  result=page.evaluate("""() => {const nav=document.querySelector('.app-bottom').getBoundingClientRect();return [...document.querySelectorAll('.act')].map(b=>{const r=b.getBoundingClientRect();const hit=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);return {width:r.width,height:r.height,bottom:r.bottom,navTop:nav.top,hit:hit===b}})}""")
  assert all(r['width']>=56 and r['height']>=56 and r['bottom']<=r['navTop']-10 and r['hit'] for r in result),result
 page.evaluate('scrollTo(0,0)');page.wait_for_timeout(60)
 assert page.evaluate("nativeMessages.filter(m=>m.kind==='topSurface').at(-1).color")==[1,1,1,1],'yellow body leaked into white status/header'
 for path in ['/matches/thread','/u/peer','/worlds/test','/settings/account']:
  page.evaluate('__fixtureOpen',path);page.wait_for_function("nativeMessages.filter(m=>m.kind==='navigation').at(-1).visible===false")
  assert page.locator('.app-bottom').evaluate('e=>getComputedStyle(e).visibility')=='hidden'
  assert page.evaluate("nativeMessages.filter(m=>m.kind==='route').at(-1).canGoBack")
  assert not page.evaluate("nativeMessages.filter(m=>m.kind==='navigation').at(-1).overlay")
 for path in ['/worlds/test','/u/peer','/matches/thread','/discover']:
  page.evaluate('__vrcrpBack()');page.wait_for_function('p=>location.pathname===p',arg=path);page.wait_for_timeout(100)
  assert page.evaluate("nativeMessages.filter(m=>m.kind==='navigation').at(-1).visible")==(path=='/discover')
 page.evaluate('__fixtureDark()');page.wait_for_function("nativeMessages.filter(m=>m.kind==='topSurface').at(-1).color[0]<.2")
 color=page.evaluate("nativeMessages.filter(m=>m.kind==='topSurface').at(-1).color");assert max(abs(a-b) for a,b in zip(color,[24/255,28/255,35/255,1]))<.0001,color
 page.evaluate('__vrcrpOpenChat("thread")');page.wait_for_function("location.pathname==='/matches/thread' && nativeMessages.filter(m=>m.kind==='route').at(-1)?.path==='/matches/thread' && nativeMessages.filter(m=>m.kind==='route').at(-1)?.canGoBack && nativeMessages.filter(m=>m.kind==='navigation').at(-1)?.visible===false")
 assert page.evaluate("nativeMessages.filter(m=>m.kind==='route').at(-1).canGoBack")
 page.locator('textarea').focus();page.set_viewport_size({'width':393,'height':434});page.evaluate('__vrcrpSetViewport({width:393,height:434,keyboardVisible:true})');page.wait_for_timeout(150)
 assert page.locator('textarea').evaluate('e=>e.getBoundingClientRect().bottom')<=434
 assert not page.evaluate("nativeMessages.filter(m=>m.kind==='navigation').at(-1).visible")
 browser.close()
print('PASS: card actions retain touch size and avoid tabs on tall/short screens; chat and deeper pages hide tabs without disabling back; return restores tabs; light/dark header color and notification deep link/keyboard')
