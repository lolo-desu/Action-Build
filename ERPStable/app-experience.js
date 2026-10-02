(() => {
  'use strict';
  const bridge = window.webkit?.messageHandlers?.erpNativeApp;
  if (window !== window.top || location.origin !== 'https://erp.sex' || !bridge) return;
  const tabPages = new Set(['/', '/discover', '/browse', '/likes', '/likes/sent', '/matches', '/posts', '/me']);
  const roots = new Set([...tabPages, '/login', '/register']);
  const refreshable = new Set(['/likes', '/likes/sent', '/matches', '/posts', '/visitors', '/notifications']);
  const css = `
    html[data-vrcrp-app="true"] .app-top {
      background: rgb(var(--surface)) !important;
      -webkit-backdrop-filter: none !important; backdrop-filter: none !important;
    }
    html[data-vrcrp-native-nav="true"] .app-bottom { opacity: 0 !important; }
    html[data-vrcrp-detail="true"] .app-bottom,
    html[data-vrcrp-keyboard="true"] .app-bottom { visibility: hidden !important; pointer-events: none !important; }
    html[data-vrcrp-app="true"] #main { padding-bottom: calc(var(--vrcrp-nav-space, 0px) + 16px) !important; }
    html[data-vrcrp-detail="true"] #main { padding-bottom: calc(16px + env(safe-area-inset-bottom)) !important; }
    html[data-vrcrp-chat="true"] #main { padding-bottom: calc(12px + env(safe-area-inset-bottom)) !important; }
    html[data-vrcrp-explore-grid="true"] .app-bottom a[href="/discover"] { color: rgb(var(--primary)) !important; font-weight: 600 !important; }
    [data-vrcrp-swipe-group="true"] { max-width: min(100%, var(--vrcrp-swipe-width)) !important; }
    [data-vrcrp-swipe-actions="true"] > * { flex-shrink: 0 !important; }
  `;
  function post(value) { try { bridge.postMessage(value); } catch {} }
  function rgba(value) {
    const match = value.match(/^rgba?\(([^)]+)\)$/);
    if (!match) return [0, 0, 0, 1];
    const numbers = match[1].split(/[\s,/]+/).filter(Boolean).map(Number);
    return [numbers[0] / 255, numbers[1] / 255, numbers[2] / 255, numbers[3] ?? 1];
  }
  function box(element, relative) {
    const r = element.getBoundingClientRect();
    return { x: r.x - (relative?.x ?? 0), y: r.y - (relative?.y ?? 0), width: r.width, height: r.height };
  }
  function setProperty(name, value) {
    const style = document.documentElement.style;
    if (style.getPropertyValue(name) !== value) style.setProperty(name, value);
  }
  let surfaceFingerprint = '';
  function updateTopSurface() {
    // Read painted CSS surfaces, never pixels from profile/chat media. A modal
    // or full-screen preview can cover the regular header without changing URL.
    const width = document.documentElement.clientWidth || innerWidth;
    const layers = document.elementsFromPoint(width / 2, 4).reverse();
    let color = [1, 1, 1, 1];
    for (const element of new Set(layers)) {
      const style = getComputedStyle(element);
      let opacity = 1;
      for (let node = element; node; node = node.parentElement) opacity *= Number(getComputedStyle(node).opacity);
      if (style.visibility === 'hidden' || opacity <= 0) continue;
      const layer = rgba(style.backgroundColor), alpha = layer[3] * opacity;
      color = color.map((value, i) => i === 3 ? 1 : layer[i] * alpha + value * (1 - alpha));
    }
    color = color.map(value => Math.round(value * 100000) / 100000);
    const fingerprint = JSON.stringify(color);
    if (fingerprint !== surfaceFingerprint) { surfaceFingerprint = fingerprint; post({ kind: 'topSurface', color }); }
  }
  function fitSwipeControls(navHeight) {
    const stage = document.querySelector('#main .stage');
    const actions = document.querySelector('#main .act-pass')?.parentElement;
    const group = stage?.parentElement;
    if (!stage || !actions || !group || !group.contains(actions)) return;
    if (location.pathname !== '/discover' || document.documentElement.dataset.vrcrpKeyboard === 'true' || innerWidth >= 1024) {
      group.removeAttribute('data-vrcrp-swipe-group'); actions.removeAttribute('data-vrcrp-swipe-actions'); return;
    }
    // Measure the site's natural size, then shrink only the card group when
    // needed. Keep the action order, button dimensions and Framer drag intact.
    group.removeAttribute('data-vrcrp-swipe-group');
    actions.dataset.vrcrpSwipeActions = 'true';
    const r = stage.getBoundingClientRect(), parent = group.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) return;
    const height = parseFloat(document.documentElement.style.getPropertyValue('--vrcrp-viewport-height')) || innerHeight;
    const gap = parseFloat(getComputedStyle(actions).columnGap) || 0;
    const intrinsic = [...actions.children].reduce((sum, el) => sum + el.getBoundingClientRect().width, 0) + gap * Math.max(0, actions.children.length - 1);
    const tail = parent.height - r.height;
    const room = height - navHeight - 12 - (r.top + scrollY) - tail;
    const width = Math.min(r.width, Math.max(210, intrinsic, room * r.width / r.height));
    setProperty('--vrcrp-swipe-width', `${Math.round(width * 100) / 100}px`);
    group.dataset.vrcrpSwipeGroup = 'true';
  }
  function navigationBlocked(nav, rect) {
    const height = parseFloat(document.documentElement.style.getPropertyValue('--vrcrp-viewport-height')) || innerHeight;
    const rendered = element => {
      const bounds = element.getBoundingClientRect();
      if (bounds.width <= 0 || bounds.height <= 0 || bounds.bottom <= 0 || bounds.top >= height) return false;
      for (let node = element; node instanceof Element; node = node.parentElement) {
        const style = getComputedStyle(node);
        if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity) === 0) return false;
      }
      return true;
    };
    // WebKit can keep the CSS viewport at its pre-keyboard height briefly.
    // A hidden source nav can therefore be outside hit testing even though the
    // native nav is correctly placed. Only an actual overlay should hide it.
    if ([...document.querySelectorAll('[data-dialog],[role="dialog"],dialog[open]')].some(rendered)) return true;
    const y = Math.min(rect.y + Math.min(15, rect.height / 2), height - 15);
    const hit = document.elementFromPoint(rect.x + rect.width / 2, Math.max(0, y));
    if (!hit || nav.contains(hit)) return false;
    const navLayer = parseInt(getComputedStyle(nav).zIndex) || 0;
    for (let node = hit; node && node !== document.body; node = node.parentElement) {
      const style = getComputedStyle(node);
      if (style.position === 'fixed' && (parseInt(style.zIndex) || 0) > navLayer && rendered(node)) return true;
    }
    return false;
  }
  const icons = new Map();
  function rasterIcon(svg, color) {
    let source = svg.outerHTML.replace(/currentColor/g, color);
    if (!svg.hasAttribute('xmlns')) source = source.replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ');
    // The source is the site's navigation SVG, never a profile or chat image.
    if (icons.has(source)) return icons.get(source);
    const promise = new Promise(resolve => {
      const image = new Image();
      image.onload = () => {
        const canvas = document.createElement('canvas');
        canvas.width = canvas.height = 66;
        canvas.getContext('2d').drawImage(image, 0, 0, 66, 66);
        resolve(canvas.toDataURL('image/png').split(',')[1]);
      };
      image.onerror = () => resolve('');
      image.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(source);
    });
    icons.set(source, promise);
    if (icons.size > 48) icons.delete(icons.keys().next().value);
    return promise;
  }
  let navFingerprint = '';
  let generation = 0;
  let queued = false;
  let ready = false;
  let routePending = false, routeAnnounced = false;
  let lastPath = location.pathname;
  let entries = [location.pathname + location.search];
  let entryKeys = [history.state?.key || 'vr-initial'];
  const views = new Map();
  const pathViews = new Map();
  let index = 0;
  let direction = 'none', pendingRestore = null, settleGeneration = 0;
  let baseIndex = Number.isInteger(history.state?.idx) ? history.state.idx : 0;
  const entryKey = () => String(entryKeys[index] || 'vr-' + index);
  function saveView() {
    const main = document.getElementById('main'); if (!main) return;
    const chat = /^\/matches\/[^/]+$/.test(lastPath), editor = chat ? main.querySelector('textarea') : null;
    const state = { x:scrollX,y:scrollY,scrollers:[...main.querySelectorAll('.overflow-y-auto,.messages')].map(e=>({top:e.scrollTop,bottom:e.scrollHeight-e.scrollTop-e.clientHeight<80})),draft:editor?.value?.slice(0,8000) || '' };
    views.delete(entryKey()); views.set(entryKey(),state); if(views.size>10)views.delete(views.keys().next().value);
    pathViews.delete(lastPath);pathViews.set(lastPath,state);if(pathViews.size>10)pathViews.delete(pathViews.keys().next().value);
  }
  function willNavigate(path, motion) {
    saveView();
    post({kind:'willNavigate',entryKey:entryKey(),toPath:path,direction:motion});
  }
  function settle() {
    const owner = ++settleGeneration, key = entryKey(), saved = pendingRestore;
    const started = performance.now();
    function attempt() {
      if(owner!==settleGeneration || key!==entryKey())return;
      const main=document.getElementById('main'), chat=/^\/matches\/[^/]+$/.test(location.pathname);
      const editor=chat?main?.querySelector('textarea'):null;
      const usable=main && (chat ? editor || main.querySelector('.card button,[role="alert"]') : main.children.length);
      const scrolls=main?[...main.querySelectorAll('.overflow-y-auto,.messages')]:[];
      const pendingHeight=saved?.scrollers?.some((s,i)=>s.top>0 && scrolls[i] && scrolls[i].scrollHeight-scrolls[i].clientHeight<s.top-1);
      if ((!usable || pendingHeight) && performance.now()-started<1400){setTimeout(attempt,35);return;}
      if(saved && main) {
        window.scrollTo(saved.x,saved.y);
        for(let i=0;i<scrolls.length;i++)if(saved.scrollers[i]){
          scrolls[i].scrollTop=saved.scrollers[i].bottom?scrolls[i].scrollHeight:saved.scrollers[i].top;
          scrolls[i].dispatchEvent(new Event('scroll'));
        }
        if(editor && saved.draft && !editor.value){
          Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set.call(editor,saved.draft);
          editor.dispatchEvent(new Event('input',{bubbles:true}));
        }
      }
      pendingRestore=null;
      requestAnimationFrame(()=>requestAnimationFrame(()=>{if(owner===settleGeneration)post({kind:'routeSettled',entryKey:key,path:location.pathname});}));
    }
    attempt();
  }
  function announceRoute() {
    post({ kind: 'route', path: location.pathname, entryKey:entryKey(),parentKey:index>0?String(entryKeys[index-1]):null,direction,showTabs: tabPages.has(location.pathname), canGoBack: index > 0 && !roots.has(location.pathname), refreshable: refreshable.has(location.pathname) });
    if (location.pathname === '/matches') window.__vrcrpSyncChats?.();
    direction='none';
  }
  async function update() {
    queued = false;
    const currentGeneration = ++generation;
    const root = document.documentElement;
    if (!root || !document.head) return;
    root.dataset.vrcrpApp = 'true';
    root.dataset.vrcrpDetail = String(!tabPages.has(location.pathname));
    root.dataset.vrcrpExploreGrid = String(location.pathname === '/browse');
    if (!document.getElementById('vrcrp-app-surfaces')) {
      const style = document.createElement('style'); style.id = 'vrcrp-app-surfaces'; style.textContent = css; document.head.appendChild(style);
    }
    if (!ready && (document.querySelector('#root')?.innerText.trim() || document.querySelector('main,form,[role="dialog"]'))) {
      ready = true; post({ kind: 'ready' });
    }
    if (routePending) {
      routePending = false;
      if (!routeAnnounced) announceRoute();
      routeAnnounced = false; settle(); lastPath = location.pathname;
    }
    if (location.pathname === '/settings/notifications' && !document.getElementById('vrcrp-system-notifications')) {
      const main = document.getElementById('main');
      if (main) {
        const card = document.createElement('section'); card.id = 'vrcrp-system-notifications'; card.className = 'card mt-4 p-4';
        const caption = document.createElement('p'); caption.textContent = 'iOS 消息通知'; caption.className = 'font-semibold';
        const button = document.createElement('button'); button.type = 'button'; button.textContent = '系统通知设置';
        button.className = 'mt-3 rounded-ctl border border-border bg-surface2 px-4 py-3 text-fg';
        button.addEventListener('click', () => post({ kind: 'notificationSettings' }));
        const description = document.createElement('p'); description.textContent = '管理横幅、锁屏提醒、声音和消息预览'; description.className = 'mt-2 text-sm text-muted';
        card.append(caption,button,description); main.appendChild(card);
      }
    }
    const nav = document.querySelector('.app-bottom');
    const anchors = nav ? [...nav.querySelectorAll('a[href]')] : [];
    const keyboard = root.dataset.vrcrpKeyboard === 'true';
    const showTabs = tabPages.has(location.pathname) && !keyboard;
    const navHeight = nav && getComputedStyle(nav).display !== 'none' ? nav.getBoundingClientRect().height : 0;
    setProperty('--vrcrp-nav-space', `${showTabs ? navHeight : 0}px`);
    fitSwipeControls(showTabs ? navHeight : 0);
    updateTopSurface();
    let model = { kind: 'navigation', visible: false, overlay: false };
    if (nav && anchors.length === 5 && getComputedStyle(nav).display !== 'none' && nav.getBoundingClientRect().width > 0) {
      const rect = nav.getBoundingClientRect();
      // Native views must not cover a site's modal, menu backdrop or lightbox.
      const overlay = navigationBlocked(nav, rect);
      const visible = showTabs && getComputedStyle(nav).visibility !== 'hidden' && !overlay;
      const navStyle = getComputedStyle(nav);
      const items = await Promise.all(anchors.map(async (a, slot) => {
        const style = getComputedStyle(a), svg = a.querySelector('svg');
        const labelNodes = [...a.childNodes].filter(n => n.nodeType === Node.TEXT_NODE && n.textContent.trim());
        const label = labelNodes.map(n => n.textContent.trim()).join(' ');
        let labelFrame = null;
        if (labelNodes.length) {
          const range = document.createRange(); range.selectNodeContents(labelNodes[labelNodes.length - 1]);
          const r = range.getBoundingClientRect(), parent = a.getBoundingClientRect();
          labelFrame = { x: r.x - parent.x, y: r.y - parent.y, width: r.width, height: r.height };
        }
        const badge = svg?.parentElement.querySelector('span');
        const badgeStyle = badge ? getComputedStyle(badge) : null;
        return {
          slot, path: new URL(a.href, location.href).pathname, title: label || a.getAttribute('aria-label') || '',
          selected: a.getAttribute('aria-current') === 'page' || location.pathname === '/browse' && new URL(a.href, location.href).pathname === '/discover', frame: box(a, rect), iconFrame: svg ? box(svg, a.getBoundingClientRect()) : null, labelFrame,
          icon: svg ? await rasterIcon(svg, getComputedStyle(svg).color) : '', color: rgba(style.color), fontSize: parseFloat(style.fontSize), bold: parseInt(style.fontWeight) >= 600, radius: parseFloat(style.borderRadius) || 0,
          badge: badge ? { title: badge.textContent, frame: box(badge, a.getBoundingClientRect()), color: rgba(badgeStyle.color), background: rgba(badgeStyle.backgroundColor) } : null,
        };
      }));
      if (currentGeneration !== generation || nav !== document.querySelector('.app-bottom')) return;
      let background = rgba(navStyle.backgroundColor);
      if (background[3] < .05) background = rgba(getComputedStyle(document.body).backgroundColor);
      const theme=getComputedStyle(root);
      model = { kind: 'navigation', visible, overlay, frame: box(nav), bottomPadding: parseFloat(navStyle.paddingBottom) || 0, background, borderColor: rgba(navStyle.borderTopColor), borderWidth: parseFloat(navStyle.borderTopWidth) || 0, selectedColor:rgba('rgb('+theme.getPropertyValue('--primary').trim()+')'),mutedColor:items.find(i=>!i.selected)?.color || [0.45,0.5,0.6,1], items };
    }
    const fingerprint = JSON.stringify(model);
    if (fingerprint !== navFingerprint) { navFingerprint = fingerprint; post(model); }
  }
  function schedule() { if (!queued) { queued = true; requestAnimationFrame(update); } }
  window.__vrcrpNativeNavReady = () => {
    const nav = document.querySelector('.app-bottom');
    if (nav) {
      document.documentElement.dataset.vrcrpNativeNav = 'true';
      nav.setAttribute('aria-hidden', 'true');
    }
  };
  window.__vrcrpNativeNavFallback = () => {
    document.documentElement.dataset.vrcrpNativeNav = 'false';
    document.querySelector('.app-bottom')?.removeAttribute('aria-hidden');
  };
  window.__vrcrpAccessibility = value => {
    document.documentElement.dataset.vrcrpReduceTransparency = String(value.reduceTransparency === true);
    document.documentElement.dataset.vrcrpReduceMotion = String(value.reduceMotion === true);
  };
  window.__vrcrpActivateTab = slot => {
    if (!tabPages.has(location.pathname) || document.documentElement.dataset.vrcrpKeyboard === 'true') return;
    const anchors = [...(document.querySelector('.app-bottom')?.querySelectorAll('a[href]') ?? [])];
    if (Number.isInteger(slot) && slot >= 0 && slot < anchors.length) {
      const anchor = anchors[slot];
      if (new URL(anchor.href, location.href).pathname === location.pathname) {
        window.scrollTo({ top: 0, behavior: document.documentElement.dataset.vrcrpReduceMotion === 'true' || matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth' });
        if (location.pathname === '/matches') window.__vrcrpSyncChats?.();
      } else anchor.click();
      return true;
    }
    return false;
  };
  window.__vrcrpBack = () => { if (index > 0 && !roots.has(location.pathname)) { saveView(); history.back();return true; } return false; };
  window.__vrcrpClearNavigation = () => { views.clear();pathViews.clear(); pendingRestore=null; };
  window.__vrcrpOpenMatches = () => {
    const link = document.querySelector('.app-bottom a[href="/matches"]');
    if (link) link.click(); else location.assign('/matches');
  };
  window.__vrcrpOpenChat = id => {
    if (typeof id !== 'string' || !/^[\w-]{1,120}$/.test(id)) return;
    const path = '/matches/' + id;
    if (location.pathname === path) return;
    const link = [...document.querySelectorAll('a[href]')].find(a => new URL(a.href, location.href).pathname === path);
    if (link) { link.click(); return; }
    const state = { usr: null, key: Math.random().toString(36).slice(2), idx: (history.state?.idx ?? 0) + 1 };
    history.pushState(state, '', path);
    window.dispatchEvent(new PopStateEvent('popstate', { state }));
  };
  for (const method of ['pushState', 'replaceState']) {
    const original = history[method];
    history[method] = function (...args) {
      let nextPath;try{nextPath=new URL(args[2] || location.href,location.href).pathname;}catch{nextPath=location.pathname;}
      const changed=nextPath!==location.pathname;
      if(changed) {
        direction=roots.has(nextPath)?(roots.has(location.pathname)?'tab':'pop'):'push';
        willNavigate(nextPath,direction);
      }
      const result = Reflect.apply(original, this, args);
      const path = location.pathname + location.search;
      if (method === 'pushState') { entries.splice(index + 1);entryKeys.splice(index+1); entries.push(path);entryKeys.push(history.state?.key || 'vr-'+Math.random().toString(36).slice(2)); index++; }
      else { entries[index] = path;entryKeys[index]=history.state?.key || entryKeys[index]; if (index === 0 && Number.isInteger(history.state?.idx)) baseIndex = history.state.idx; }
      if(changed)pendingRestore=views.get(entryKey()) || pathViews.get(location.pathname) || null;
      // Tell UIKit the new history key before waiting for a paint frame.
      // A quick nested gesture must use the latest parent even during layout.
      announceRoute(); routeAnnounced = true; lastPath = location.pathname;
      routePending = true; schedule();
      return result;
    };
  }
  window.addEventListener('popstate', event => {
    const path = location.pathname + location.search;
    if(!event.isTrusted && entries[index]===path && Number.isInteger(history.state?.idx) && history.state.idx-baseIndex===index)return;
    const oldIndex=index;
    saveView();
    const target = Number.isInteger(history.state?.idx) ? history.state.idx - baseIndex : -1;
    index = target >= 0 && target < entries.length && entries[target] === path ? target : Math.max(0, entries.lastIndexOf(path));
    direction=index<oldIndex?'pop':index>oldIndex?'push':'none';
    pendingRestore=views.get(entryKey()) || null;
    announceRoute(); routeAnnounced = true; lastPath = location.pathname;
    routePending = true; schedule();
  });
  document.addEventListener('click', event => {
    if (!event.isTrusted) return;
    const el = event.target instanceof Element ? event.target : event.target.parentElement;
    const control = el?.closest('button,[role="button"],.app-bottom a');
    if (control && !control.matches(':disabled,[aria-disabled="true"]')) post({ kind: 'haptic', style: control.closest('.app-bottom') ? 'selection' : 'light' });
  }, { passive: true, capture: true });
  document.addEventListener('pointerdown',event=>{
    const a=event.target.closest?.('a[href]');if(!a)return;
    try{const url=new URL(a.href,location.href);if(url.origin===location.origin&&url.pathname!==location.pathname&&!roots.has(url.pathname))post({kind:'willNavigate',entryKey:entryKey(),toPath:url.pathname,direction:'push'});}catch{}
  },{passive:true,capture:true});
  // Observe successful operations without reading request/response bodies or
  // changing the site's promises, errors, animation timing or event handlers.
  const originalFetch = window.fetch;
  window.fetch = function (...args) {
    const promise = Reflect.apply(originalFetch, this, args);
    let url, method;
    try { url = new URL(args[0] instanceof Request ? args[0].url : String(args[0]), location.href); method = args[1]?.method ?? (args[0] instanceof Request ? args[0].method : 'GET'); } catch {}
    if (url?.origin === location.origin && String(method).toUpperCase() === 'POST' && (url.pathname === '/api/v1/swipes' || /^\/api\/v1\/matches\/[^/]+\/messages$/.test(url.pathname))) {
      promise.then(response => { if (response.ok) post({ kind: 'haptic', style: url.pathname === '/api/v1/swipes' ? 'light' : 'success' }); }).catch(() => {});
    }
    return promise;
  };
  new MutationObserver(records => {
    if (!ready || records.some(record => record.type !== 'attributes' || record.target === document.documentElement || record.target === document.body || record.target.closest?.('.app-bottom,.app-top,[role="dialog"],.dialog-panel') || record.attributeName === 'open')) schedule();
  }).observe(document, { subtree: true, childList: true, attributes: true, characterData: true, attributeFilter: ['class', 'style', 'aria-current', 'open', 'data-preset', 'data-theme', 'data-vrcrp-keyboard'] });
  window.addEventListener('resize', schedule);
  window.addEventListener('scroll', schedule, { passive: true });
  let snapshotTimer;
  const snapshotSoon=()=>{clearTimeout(snapshotTimer);snapshotTimer=setTimeout(()=>post({kind:'viewUpdated',entryKey:entryKey()}),160);};
  window.addEventListener('scroll',snapshotSoon,{passive:true,capture:true});
  new MutationObserver(records=>{if(records.some(r=>r.target.closest?.('#main') && (r.type!=='attributes' || r.attributeName==='aria-current')))snapshotSoon();}).observe(document,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['aria-current']});
  document.addEventListener('focusin', schedule);
  routePending = true; schedule();
})();
