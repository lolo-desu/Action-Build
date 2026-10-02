"""Exercise the original site's installed-app touch refresh handler (index-BMh-o0xT)."""
from pathlib import Path
import os,subprocess
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[1]
modules=Path(os.environ.get('TEST_NODE_MODULES','/workspace/vrcrp-test-tools/node_modules'))
original=r'''const ec=72,eE=110,tE=/^\/(discover|matches\/[^/]+)\/?$/;function nE(r){for(let n=r;n&&n!==document.body&&n!==document.documentElement;n=n.parentElement)if(n.scrollTop>0)return!0;return!1}function rE(){const{pathname:r}=yt(),[n,s]=_.useState(0),[o,l]=_.useState(!1),u=_.useRef(r);if(u.current=r,_.useEffect(()=>{if(!Ba())return;let p=0,m=0,g=!1,y=!1,x=0;const w=()=>{g=!1,y=!1,x=0,s(0)},L=E=>{if(g=!1,E.touches.length!==1||window.scrollY>0||tE.test(u.current))return;const z=E.target instanceof Element?E.target:null;z!=null&&z.closest('[role="dialog"], [data-no-ptr], input, textarea, select')||nE(z)||(p=E.touches[0].clientY,m=E.touches[0].clientX,g=!0,y=!1)},j=E=>{if(!g)return;const z=E.touches[0].clientY-p,D=E.touches[0].clientX-m;if(!y){if(Math.abs(D)<8&&Math.abs(z)<8)return;if(z<=0||Math.abs(D)>z||window.scrollY>0){w();return}y=!0}x=Math.min(eE,Math.max(0,z*.5)),s(x)},k=()=>{if(g){if(y&&x>=ec){l(!0),s(ec),window.location.reload();return}w()}};return window.addEventListener("touchstart",L,{passive:!0}),window.addEventListener("touchmove",j,{passive:!0}),window.addEventListener("touchend",k,{passive:!0}),window.addEventListener("touchcancel",w,{passive:!0}),()=>{window.removeEventListener("touchstart",L),window.removeEventListener("touchmove",j),window.removeEventListener("touchend",k),window.removeEventListener("touchcancel",w)}},[]),n<=0&&!o)return null;const d=n>=ec;return f.jsx("div",{"aria-hidden":"true",className:"pointer-events-none fixed inset-x-0 z-[60] flex justify-center",style:{top:"calc(env(safe-area-inset-top) + 8px)",transform:`translateY(${n-40}px)`,opacity:Math.min(1,n/40)},children:f.jsx("span",{className:re("grid h-10 w-10 place-items-center rounded-full border border-border bg-surface shadow-lg transition-colors",d?"text-primary":"text-muted"),children:f.jsx(t2,{className:re("h-5 w-5",o&&"animate-spin"),style:o?void 0:{transform:`rotate(${n*3}deg)`}})})})}'''
source=root/'build/refresh-original-fixture.js';bundle=root/'build/refresh-original-bundle.js'
source.parent.mkdir(exist_ok=True)
source.write_text("import * as _ from 'react';import * as f from 'react/jsx-runtime';import {createRoot} from 'react-dom/client';const Ba=()=>navigator.standalone;const yt=()=>({pathname:location.pathname});const re=(...a)=>a.filter(Boolean).join(' ');const t2=p=>f.jsx('svg',p);"+original+"function Probe(){_.useEffect(()=>{window.refreshFixtureReady=true},[]);return f.jsx(rE,{})}createRoot(document.getElementById('root')).render(f.jsx(Probe,{}));")
subprocess.run([str(modules/'.bin/esbuild'),str(source),'--bundle','--format=esm','--outfile='+str(bundle)],check=True,env={**os.environ,'NODE_PATH':str(modules)},capture_output=True)
html='<html><head><style>.fixed{position:fixed;top:8px;width:40px;height:40px}.fixed span{display:block;width:40px;height:40px;border-radius:50%;border:1px solid black}</style></head><body><main id="main">Test content</main><div id="root"></div><script type="module" src="/fixture.js"></script></body></html>'
with sync_playwright() as p:
    browser=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
    for integrated in [False,True]:
        documents=[]
        page=browser.new_page(viewport={'width':393,'height':793},is_mobile=True,has_touch=True)
        page.add_init_script("Object.defineProperty(navigator,'standalone',{get:()=>true,configurable:true})")
        if integrated:
            page.add_init_script((root/'ERPStable/page-surfaces.js').read_text())
            page.add_init_script((root/'ERPStable/interaction.js').read_text())
        def handle(route):
            if route.request.url.endswith('/fixture.js'):route.fulfill(body=bundle.read_text(),content_type='text/javascript')
            else:documents.append(route.request.url);route.fulfill(body=html,content_type='text/html')
        page.route('https://erp.sex/**',handle);page.goto('https://erp.sex/matches')
        page.wait_for_function('window.refreshFixtureReady')
        page.evaluate("""window.fixtureTouches=0;document.getElementById('main').addEventListener('touchmove',()=>fixtureTouches++);
window.fixtureTouch=(type,y)=>{const e=new Event(type,{bubbles:true});Object.defineProperty(e,'touches',{value:type==='touchend'?[]:[{clientX:100,clientY:y}]});document.getElementById('main').dispatchEvent(e)};
fixtureTouch('touchstart',10);fixtureTouch('touchmove',190)""")
        if integrated:
            page.wait_for_timeout(100)
            assert page.locator('.pointer-events-none.fixed').count()==0,'duplicate circular PWA refresh appeared'
            assert page.evaluate('fixtureTouches')==1,'native refresh suppression blocked content touch events'
            page.evaluate("fixtureTouch('touchend',190)");page.wait_for_timeout(180)
            assert len(documents)==1,'PWA refresh still reloaded the document'
            assert page.evaluate("document.documentElement.matches('[data-no-ptr]')")
        else:
            page.wait_for_selector('.pointer-events-none.fixed',state='attached')
            page.evaluate("fixtureTouch('touchend',190)")
            page.wait_for_function('window.refreshFixtureReady')
            assert len(documents)>=2,'baseline did not exercise the original site full reload'
        page.close()
    browser.close()
print('PASS: original PWA touch refresh renders/reloads in baseline; app suppresses duplicate round indicator and reload through the supported opt-out; content touch events remain active')

