from pathlib import Path
import os
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[1]
html='''<html><head><meta charset="utf-8"><style>:root{--primary:237 83 82;--surface:255 255 255;--muted:118 130 151}body{margin:0}.app-top{height:55px}main{padding:16px}.stage{height:60px;touch-action:none}.carousel{height:70px;width:260px;overflow-x:auto}.wide{width:1000px;height:60px}button{height:35px}article{height:80px}</style></head><body><header class="app-top">导航</header><main id="main"><article><p id="message">聊天文字可以选择复制</p><p id="post">帖子正文可以选择复制</p></article><section class="card"><h2>资料卡</h2><div id="intro">简介与公开资料内容</div></section><div class="stage"><p id="drag">划卡区域</p></div><div class="carousel"><div class="wide">横向内容</div></div><button id="action">操作按钮</button></main></body></html>'''
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH','/usr/bin/chromium'),args=['--no-sandbox'])
 page=browser.new_page(viewport={'width':393,'height':793})
 page.add_init_script('window.nativeMessages=[];window.webkit={messageHandlers:{erpNativeApp:{postMessage:m=>nativeMessages.push(m)}}}')
 for name in ['interaction','app-experience','content-experience']:page.add_init_script((root/'ERPStable'/f'{name}.js').read_text())
 page.route('https://erp.sex/**',lambda r:r.fulfill(body=html,content_type='text/html'));page.goto('https://erp.sex/posts/test')
 for selector in ['#message','#post','#intro']:
  assert page.locator(selector).evaluate('e=>getComputedStyle(e).userSelect')=='text'
  assert page.locator(selector).evaluate("e=>{const ev=new MouseEvent('contextmenu',{bubbles:true,cancelable:true});return e.dispatchEvent(ev)}")
 for selector in ['#drag','#action']:
  assert page.locator(selector).evaluate('e=>getComputedStyle(e).userSelect')=='none'
  assert not page.locator(selector).evaluate("e=>{const ev=new MouseEvent('contextmenu',{bubbles:true,cancelable:true});return e.dispatchEvent(ev)}")
 page.wait_for_function("nativeMessages.some(m=>m.kind==='gestureZones')")
 zones=page.evaluate("nativeMessages.filter(m=>m.kind==='gestureZones').at(-1).zones")
 for selector in ['.stage','.carousel','#action']:
  r=page.locator(selector).bounding_box();x,y=r['x']+r['width']/2,r['y']+r['height']/2
  assert any(z['x']<=x<=z['x']+z['width'] and z['y']<=y<=z['y']+z['height'] for z in zones),(selector,zones)
 page.evaluate("const main=document.getElementById('main');main.style.height='220px';main.style.overflowY='auto'")
 page.wait_for_function("nativeMessages.filter(m=>m.kind==='gestureZones').at(-1).zones.every(z=>z.y+z.height<=document.getElementById('main').getBoundingClientRect().bottom+1)")
 page.evaluate("document.getElementById('main').scrollTop=170")
 page.wait_for_function("nativeMessages.filter(m=>m.kind==='gestureZones').at(-1).zones.some(z=>z.y<=document.querySelector('.carousel').getBoundingClientRect().top+1&&z.y+z.height>=document.querySelector('.carousel').getBoundingClientRect().bottom-1)")
 page.evaluate("document.getElementById('main').scrollTop=0")
 page.evaluate("const range=document.createRange();range.selectNodeContents(document.getElementById('message'));getSelection().removeAllRanges();getSelection().addRange(range)")
 page.wait_for_function("nativeMessages.some(m=>m.kind==='selection'&&m.selected)")
 assert page.evaluate('getSelection().toString()')=='聊天文字可以选择复制'
 page.evaluate('getSelection().removeAllRanges()');page.wait_for_function("nativeMessages.filter(m=>m.kind==='selection').at(-1).selected===false")
 page.emulate_media(reduced_motion='reduce');page.click('#action')
 assert page.locator('#action').evaluate('e=>e.getAnimations().length')==0
 browser.close()
print('PASS: chat/post/profile text selection and context menus; card/control exclusion; horizontal zones follow nested scroll and clipping; selection suspends back; reduced-motion animation behavior')
