from pathlib import Path
import os,subprocess
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[1]
modules=Path(os.environ.get('TEST_NODE_MODULES','/workspace/vrcrp-test-tools/node_modules'))
bundle=root/'build/swipe-fixture.js'
subprocess.run([str(modules/'.bin/esbuild'),str(root/'scripts/swipe-fixture.jsx'),'--bundle','--format=esm','--platform=browser','--outfile='+str(bundle)],check=True,env={**os.environ,'NODE_PATH':str(modules)},capture_output=True)
html='''<html><head><style>:root{--surface:255 255 255;--primary:237 83 82}*{box-sizing:border-box}body{margin:0;font:16px system-ui}.app-top{height:56px}main{padding:20px 12px}.deck{max-width:320px;margin:auto}.stage{position:relative;aspect-ratio:3/4.3;background:#aaa}.absolute{position:absolute}.inset-0{inset:0}.photo{height:100%;display:grid;place-items:center}.touch-none{touch-action:none}.pointer-events-none{pointer-events:none}.border-4{border:4px solid;font-size:30px;padding:4px 12px;font-weight:900;background:#fffc}.border-success{border-color:#15803d;color:#15803d}.border-danger{border-color:#b91c1c;color:#b91c1c}.border-accent{border-color:#eab308;color:#141414}.left-6{left:24px}.right-6{right:24px}.top-24{top:96px}.bottom-40{bottom:160px;left:40px}.actions{display:flex;justify-content:center;gap:14px;margin-top:20px}.act{width:64px;height:64px;border-radius:50%;background:white;border:2px solid black}.act-super{width:56px;height:56px}.app-bottom{position:fixed;bottom:0;height:70px;width:100%;background:white}</style></head><body><header class="app-top">测试</header><div id="root"></div><nav class="app-bottom"></nav><script type="module" src="/fixture.js"></script></body></html>'''
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH','/usr/bin/chromium'),args=['--no-sandbox'])
 page=browser.new_page(viewport={'width':393,'height':793})
 page.add_init_script("window.webkit={messageHandlers:{erpNativeApp:{postMessage(){}}}}")
 page.add_init_script((root/'ERPStable/app-experience.js').read_text());page.add_init_script((root/'ERPStable/swipe-feedback.js').read_text())
 page.route('https://erp.sex/**',lambda r:r.fulfill(body=bundle.read_text() if r.request.url.endswith('/fixture.js') else html,content_type='text/javascript' if r.request.url.endswith('/fixture.js') else 'text/html'))
 page.goto('https://erp.sex/discover');page.wait_for_selector('.cursor-grab');page.wait_for_timeout(100)
 bounds=page.locator('.stage').bounding_box();x=bounds['x']+bounds['width']/2;y=bounds['y']+bounds['height']/2
 for kind,dx,dy in [('like',68,0),('pass',-68,0),('super',0,-68)]:
  page.mouse.move(x,y);page.mouse.down();page.mouse.move(x+dx,y+dy,steps=10);page.wait_for_timeout(80)
  el=page.locator('[data-vrcrp-stamp="'+kind+'"]')
  values=el.evaluate('e=>({opacity:+getComputedStyle(e).opacity,bg:getComputedStyle(e).backgroundColor,events:getComputedStyle(e).pointerEvents})')
  assert values['opacity']>=.9 and values['bg']=='rgb(255, 255, 255)' and values['events']=='none',values
  assert all(page.locator('[data-vrcrp-stamp="'+other+'"]').evaluate('e=>+getComputedStyle(e).opacity')==0 for other in ['like','pass','super'] if other!=kind)
  page.mouse.move(x,y,steps=10);page.wait_for_timeout(180);page.mouse.up();page.wait_for_timeout(350)
  assert page.evaluate('swipes.length')==0,'label enhancement changed drag commit/cancel behavior'
 # The original threshold still commits exactly one swipe; buttons stay unchanged.
 page.mouse.move(x,y);page.mouse.down();page.mouse.move(x+160,y,steps=14);page.wait_for_timeout(150);page.mouse.up();page.wait_for_timeout(350)
 assert page.evaluate('swipes')==['right']
 for selector,value,size in [('.act-pass','left',64),('.act-super','up',56),('.act-like','right',64)]:
  assert page.locator(selector).bounding_box()['width']==size
  page.click(selector);assert page.evaluate('swipes.at(-1)')==value
 browser.close()
print('PASS: real Framer Motion like/pass/super drag labels show earlier with contrast; direction, cancellation, original thresholds and button sizes/actions preserved')
