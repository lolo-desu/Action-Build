"""Test against real React 18 and TanStack Query, with local fake API data."""
from pathlib import Path
import json,os,subprocess
from urllib.parse import urlparse,parse_qs
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[1]
modules=Path(os.environ.get('TEST_NODE_MODULES','/workspace/vrcrp-test-tools/node_modules'))
bundle=root/'build/cache-fixture.js';bundle.parent.mkdir(exist_ok=True)
subprocess.run([str(modules/'.bin/esbuild'),str(root/'scripts/cache-fixture.jsx'),'--bundle','--format=esm','--platform=browser','--outfile='+str(bundle)],check=True,env={**os.environ,'NODE_PATH':str(modules)},capture_output=True)
old={'id':'old','matchId':'thread','senderId':'peer','type':'text','text':'原有消息','createdAt':'2020-01-01T00:00:00Z'}
server={'active':{'items':[{'id':'thread','user':{'displayName':'测试联系人'},'unreadCount':3,'lastMessage':old}], 'nextCursor':None},'unmatched':{'items':[{'id':'closed','user':{'displayName':'已结束联系人'},'unreadCount':0}], 'nextCursor':None},'messages':{'items':[old],'hasMore':False},'offline':False}
requests=[]
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH','/usr/bin/chromium'),args=['--no-sandbox'])
 page=browser.new_page(viewport={'width':393,'height':793},is_mobile=True,has_touch=True)
 page.add_init_script("window.nativeMessages=[];window.webkit={messageHandlers:{erpNativeApp:{postMessage:m=>nativeMessages.push(m)},erpNativeNotifications:{postMessage:m=>nativeMessages.push(m)}}}")
 for name in ['site-cache','notifications','app-experience']:page.add_init_script((root/'ERPStable'/f'{name}.js').read_text())
 def handle(route):
  url=urlparse(route.request.url);q=parse_qs(url.query)
  if url.path.startswith('/api/'):
   requests.append((url.path,q,route.request.method))
   if server['offline']:route.abort();return
   if url.path.endswith('/me/counters'):value={'unreadMessages':server['active']['items'][0]['unreadCount']}
   elif url.path.endswith('/me'):value={'id':'self'}
   elif url.path.endswith('/messages'):value=server['messages']
   elif url.path.endswith('/matches'):value=server.get('older',server['active']) if q.get('cursor') else server[q.get('state',['active'])[0]]
   else:value={'id':url.path.rsplit('/',1)[-1],'user':{'displayName':'测试联系人'},'state':'active'}
   route.fulfill(body=json.dumps(value),content_type='application/json')
  elif url.path.endswith('index-test.js'):route.fulfill(body=bundle.read_text(),content_type='text/javascript')
  else:route.fulfill(body='<html><head><style>:root{--surface:255 255 255;--primary:237 83 82}body{margin:0}.app-top{height:56px}.messages{height:300px;overflow:auto}li a{display:block;padding:12px}span{margin-left:12px}</style></head><body><div id="root"></div><script type="module" src="/assets/index-test.js"></script></body></html>',content_type='text/html')
 page.route('https://erp.sex/**',handle);page.goto('https://erp.sex/matches')
 page.wait_for_selector('.unread');page.wait_for_function("nativeMessages.some(m=>m.kind==='session'&&m.userId==='self')")
 # No WebSocket exists. A native sync must still update the rendered query.
 server['active']['items'][0]['unreadCount']=5;server['active']['items'][0]['lastMessage']={**old,'id':'updated','text':'已更新状态'}
 page.evaluate('__vrcrpSyncChats()');page.wait_for_function("document.querySelector('.unread').textContent==='5' && document.querySelector('.preview').textContent==='已更新状态'")
 assert page.evaluate("fixtureClient.getQueryData(['m','sfw','zh','matches','active']).pages[0].items[0].unreadCount")==5
 page.click('.closed-tab');page.wait_for_selector('a[href="/matches/closed"]')
 assert page.evaluate("fixtureClient.getQueryData(['m','sfw','zh','matches','active']).pages[0].items.map(m=>m.id)")==['thread'],'closed responses overwrote active cache'
 server['unmatched']['items'][0]['user']['displayName']='结束状态已更新'
 page.evaluate('__vrcrpSyncChats()');page.wait_for_function("document.querySelector('a[href=\"/matches/closed\"]').textContent.includes('结束状态已更新')")
 page.click('.active-tab');page.wait_for_selector('a[href="/matches/thread"]');page.click('a[href="/matches/thread"]')
 page.wait_for_selector('[data-id="old"]');page.wait_for_function("nativeMessages.filter(m=>m.kind==='route').at(-1).direction==='push'")
 page.locator('textarea').fill('未发送草稿');page.evaluate("fixtureOpen('/u/peer')")
 assert page.evaluate("nativeMessages.filter(m=>m.kind==='route').at(-1).path")=='/u/peer','route announcement waited for a paint frame'
 routes=page.evaluate("nativeMessages.filter(m=>m.kind==='route')")
 assert routes[-1]['parentKey']==next(r['entryKey'] for r in reversed(routes[:-1]) if r['path']=='/matches/thread'),'nested parent is not the chat'
 page.wait_for_function("location.pathname==='/u/peer'");page.evaluate('__vrcrpBack()');page.wait_for_selector('textarea');page.wait_for_function("document.querySelector('textarea').value==='未发送草稿'")
 page.evaluate('__vrcrpBack()');page.wait_for_selector('.active-tab')
 # A warm chat must open with an unreachable API and no document/module reload.
 server['offline']=True;page.evaluate('fixtureOpen("/matches/thread")');page.wait_for_selector('[data-id="old"]',timeout=1000)
 assert page.evaluate('fixtureBoots')==1
 page.wait_for_function("document.querySelector('textarea').value==='未发送草稿'",timeout=1000)
 # Background revalidation supplies real server messages to the mounted chat.
 server['offline']=False;new={**old,'id':'new-real','text':'后台同步的新消息','createdAt':'2026-10-02T12:00:00Z'};server['messages']['items'].append(new)
 page.evaluate('__vrcrpSiteCache.refreshChat()');page.wait_for_selector('[data-id="new-real"]')
 assert page.locator('[data-id="old"]').count()==1
 assert not any(method!='GET' for _,_,method in requests),'cache/prefetch wrote server state'
 # A cursor response must keep the first page rather than replace it.
 page.evaluate('__vrcrpBack()');page.wait_for_selector('.more')
 server['active']['nextCursor']='older'
 server['older']={'items':[{'id':'older-thread','user':{'displayName':'更早的联系人'},'unreadCount':0}],'nextCursor':None}
 page.evaluate('__vrcrpSyncChats()');page.wait_for_function("fixtureClient.getQueryData(['m','sfw','zh','matches','active']).pages[0].nextCursor==='older'")
 page.click('.more');page.wait_for_selector('a[href="/matches/older-thread"]')
 assert page.evaluate("fixtureClient.getQueryData(['m','sfw','zh','matches','active']).pages.map(p=>p.items.map(m=>m.id))")==[['thread'],['older-thread']],'cursor response replaced page one'
 # A new account cannot consume the previous user's warm responses.
 page.evaluate("__vrcrpSiteCache.session('other',{'X-Content-Mode':'sfw','Accept-Language':'zh'})")
 server['offline']=True
 assert page.evaluate("fetch('/api/v1/matches/thread/messages?limit=50').then(()=>false,()=>true)")
 browser.close()
print('PASS: real React/TanStack cache updates without WS; active/closed isolation and pagination; warm chat offline; draft restoration; real-message background merge; no reload/server writes/account cache reuse')
