"""Exercise actual browser history while navigation paints are unavailable."""
from pathlib import Path
import os
from playwright.sync_api import sync_playwright

root=Path(__file__).resolve().parents[1]
fixture=(root/'scripts/navigation-fixture.html').read_text()
with sync_playwright() as p:
    engine=os.environ.get('NAV_TEST_ENGINE','chromium')
    browser=p.webkit.launch() if engine=='webkit' else p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
    page=browser.new_page(viewport={'width':393,'height':793},has_touch=True)
    page.add_init_script("window.nativeMessages=[];window.webkit={messageHandlers:{erpNativeApp:{postMessage:m=>nativeMessages.push(m)}}}")
    for name in ['keyboard','app-experience','page-surfaces']:
        page.add_init_script((root/'ERPStable'/f'{name}.js').read_text())
    page.route('https://erp.sex/**',lambda r:r.fulfill(body=fixture,content_type='text/html'))
    page.goto('https://erp.sex/matches')
    page.wait_for_function("nativeMessages.some(m=>m.kind==='routeSettled')")
    page.evaluate('window.originalAnimationFrame=requestAnimationFrame;window.requestAnimationFrame=()=>0')
    page.evaluate("__fixtureOpen('/matches/thread');window.pendingEntryKey=history.state.key;const a=document.createElement('a');a.href='/matches/thread';document.getElementById('main').append(a);__vrcrpPageBack();a.click()")
    page.wait_for_function("location.pathname==='/matches/thread'&&history.state.idx===1&&history.state.key!==pendingEntryKey",polling=20)
    page.evaluate('__vrcrpPageBack()')
    page.wait_for_function("location.pathname==='/matches'",polling=20)
    # A back followed immediately by a tap must replay the new tap on the
    # restored list, rather than lose it to an outstanding browser traversal.
    for i in range(20):
        page.evaluate("__fixtureOpen('/matches/thread');document.querySelector('textarea').value='未发送草稿';__vrcrpPageBack()")
        page.wait_for_function("location.pathname==='/matches'",polling=20)
        page.locator('a[href="/matches/thread"]').click()
        page.wait_for_function("location.pathname==='/matches/thread'&&document.querySelector('textarea').value==='未发送草稿'",polling=20)
        page.evaluate('__vrcrpPageBack()')
        page.wait_for_function("location.pathname==='/matches'",polling=20)
    # One intent per level, even when all three are submitted in one task.
    page.evaluate("__fixtureOpen('/matches/thread');__fixtureOpen('/u/peer');__fixtureOpen('/posts/detail');__vrcrpPageBack();__vrcrpPageBack();__vrcrpPageBack()")
    page.wait_for_function("location.pathname==='/matches'&&history.state.idx===0",polling=20)
    assert not page.evaluate('__vrcrpPageBack()'),'back escaped the app root'
    # Returning with a focused textarea must save its value before blur.
    page.evaluate("__fixtureOpen('/matches/thread');document.querySelector('textarea').value='键盘草稿';document.querySelector('textarea').focus();__vrcrpPageBack()")
    page.wait_for_function("location.pathname==='/matches'",polling=20)
    page.evaluate("__fixtureOpen('/matches/thread')")
    page.wait_for_function("document.querySelector('textarea').value==='键盘草稿'",polling=20)
    page.evaluate("document.querySelector('textarea').focus();document.activeElement.blur();__vrcrpPageBack()")
    page.wait_for_function("location.pathname==='/matches'",polling=20)
    # A slow page remains returnable before its content arrives.
    page.evaluate("__fixtureOpen('/u/loading');document.getElementById('main').innerHTML='<div class=animate-spin>Loading</div>';__vrcrpPageBack()")
    page.wait_for_function("location.pathname==='/matches'",polling=20)
    page.wait_for_function("nativeMessages.filter(m=>m.kind==='routeSettled').at(-1)?.entryKey===history.state.key",polling=20)
    assert page.evaluate("performance.getEntriesByType('navigation').length")==1
    routes=page.evaluate("nativeMessages.filter(m=>m.kind==='route')")
    assert routes[-1]['path']=='/matches' and not routes[-1]['canGoBack']
    page.evaluate('window.requestAnimationFrame=originalAnimationFrame;dispatchEvent(new Event("resize"))')
    browser.close()
print(f'PASS ({engine}): 20 rapid re-entry cycles; queued nested returns; focused/dismissed input draft retention; slow-page return; no paint dependency or document reload')
