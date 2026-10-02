from pathlib import Path
import os
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[1];fixture=(root/'scripts/surface-fixture.html').read_text()
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH','/usr/bin/chromium'),args=['--no-sandbox'])
 page=browser.new_page(viewport={'width':393,'height':793},is_mobile=True,has_touch=True)
 page.add_init_script("window.nativeMessages=[];window.webkit={messageHandlers:{erpNativeApp:{postMessage:m=>nativeMessages.push(m)}}}")
 for name in ['page-surfaces','interaction','keyboard','app-experience']:page.add_init_script((root/'ERPStable'/f'{name}.js').read_text())
 page.route('https://erp.sex/**',lambda r:r.fulfill(body=fixture,content_type='text/html'));page.goto('https://erp.sex/me')
 page.wait_for_function("document.querySelector('[data-vrcrp-install]')")
 assert page.evaluate('navigator.standalone') is True
 assert not page.get_by_role('button',name='加入主屏幕').is_visible()
 root_key=page.evaluate("nativeMessages.filter(m=>m.kind==='route').at(-1).entryKey")
 page.evaluate("__surfaceOpen('/profile/edit/basics')");page.wait_for_selector('[data-vrcrp-page-back]')
 entry_index=page.evaluate('history.state.idx');history_length=page.evaluate('history.length')
 for path in ['/profile/edit/about','/profile/edit/photos','/profile/edit']:
  page.evaluate('__surfaceOpen',path);page.wait_for_function('p=>nativeMessages.filter(m=>m.kind===\'route\').at(-1).path===p',arg=path)
  route=page.evaluate("nativeMessages.filter(m=>m.kind==='route').at(-1)")
  assert route['direction']=='tab' and route['parentKey']==root_key,route
  assert page.evaluate('history.state.idx')==entry_index and page.evaluate('history.length')==history_length
 page.locator('[data-vrcrp-page-back]').click();page.wait_for_function("location.pathname==='/me'")
 page.evaluate("__surfaceOpen('/matches/thread')");page.wait_for_selector('[data-vrcrp-chat-bar]')
 assert not page.locator('.app-top').is_visible()
 assert page.locator('[data-vrcrp-chat-bar]').bounding_box()['y']==0
 for width in [393,320,430,393]:
  page.set_viewport_size({'width':width,'height':793})
  page.wait_for_function("Math.abs(document.querySelector('[data-vrcrp-chat-bar]').getBoundingClientRect().left)<1&&Math.abs(document.querySelector('[data-vrcrp-chat-bar]').getBoundingClientRect().right-innerWidth)<1")
 assert page.locator('#main').evaluate('e=>parseFloat(getComputedStyle(e).paddingBottom)')==6
 assert page.evaluate("document.documentElement.matches('[data-no-ptr]')")
 page.evaluate('__vrcrpChatUnread(7)');assert page.locator('[data-vrcrp-unread]').inner_text()=='7'
 page.evaluate('__vrcrpChatUnread(100)');assert page.locator('[data-vrcrp-unread]').inner_text()=='99+'
 page.evaluate('__vrcrpChatUnread(0)');assert not page.locator('[data-vrcrp-unread]').is_visible()
 page.locator('a[href="/u/peer"]').click();page.wait_for_selector('[data-vrcrp-page-back]');page.evaluate('__vrcrpPageBack()');page.wait_for_function("location.pathname==='/matches/thread'")
 page.locator('[data-vrcrp-chat-back]').click();page.wait_for_function("location.pathname==='/me'")
 page.evaluate("__surfaceOpen('/matches')");page.wait_for_timeout(100);before=page.locator('.app-top').bounding_box()
 page.evaluate('__vrcrpPullSurface(66)');assert page.locator('.app-top').bounding_box()==before
 assert page.locator('#main').evaluate('e=>getComputedStyle(e).transform')=='matrix(1, 0, 0, 1, 0, 66)'
 assert page.evaluate("nativeMessages.filter(m=>m.kind==='topSurface').at(-1).color")==[1,1,1,1]
 page.evaluate("document.documentElement.style.setProperty('--surface','24 28 35')")
 page.wait_for_function("nativeMessages.filter(m=>m.kind==='topSurface').at(-1).color[0]===24/255")
 page.evaluate("document.querySelector('.app-top').style.transform='translateY(150px)';__vrcrpPullSurface(66);window.dispatchEvent(new Event('scroll'))")
 page.wait_for_timeout(100)
 assert page.evaluate("nativeMessages.filter(m=>m.kind==='topSurface').at(-1).color")==[24/255,28/255,35/255,1]
 page.evaluate("document.querySelector('.app-top').style.removeProperty('transform');document.documentElement.style.setProperty('--surface','255 255 255')")
 page.evaluate('__vrcrpPullSurface(0)');page.wait_for_timeout(200)
 page.evaluate("__surfaceOpen('/discover')");page.wait_for_timeout(100);page.evaluate('__surfaceOverlay()');page.wait_for_function("nativeMessages.some(m=>m.kind==='profileOverlay'&&m.visible)")
 page.wait_for_selector('[data-vrcrp-profile-overlay]');assert page.evaluate('__vrcrpPageBack()')
 page.wait_for_function("nativeMessages.filter(m=>m.kind==='profileOverlay').at(-1).visible===false")
 assert page.evaluate('location.pathname')=='/discover'
 browser.close()
print('PASS: installed-app controls hidden; peer chat header/unread badge; editor tabs replace one history level; routed and overlay profile return; fixed header during pull')
