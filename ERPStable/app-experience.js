(() => {
  'use strict';
  const bridge = window.webkit?.messageHandlers?.erpNativeApp;
  if (window !== window.top || location.origin !== 'https://erp.sex' || !bridge) return;
  const roots = new Set(['/', '/discover', '/browse', '/likes', '/matches', '/posts', '/me', '/login', '/register']);
  const refreshable = new Set(['/likes', '/likes/sent', '/matches', '/posts', '/visitors', '/notifications']);
  const css = `
    html[data-vrcrp-app="true"] .app-top,
    html[data-vrcrp-app="true"] .app-bottom {
      background: rgb(var(--surface) / .79) !important;
      -webkit-backdrop-filter: blur(24px) saturate(1.55) !important;
      backdrop-filter: blur(24px) saturate(1.55) !important;
      box-shadow: inset 0 1px 0 rgb(255 255 255 / .22), 0 5px 18px rgb(0 0 0 / .035);
    }
    html[data-vrcrp-app="true"] .dialog-panel {
      background: rgb(var(--surface) / .88) !important;
      -webkit-backdrop-filter: blur(28px) saturate(1.45) !important;
      backdrop-filter: blur(28px) saturate(1.45) !important;
      box-shadow: inset 0 1px 0 rgb(255 255 255 / .24), 0 20px 64px rgb(0 0 0 / .16);
    }
    html[data-vrcrp-native-nav="true"] .app-bottom { opacity: 0 !important; }
    @keyframes vrcrp-page-arrive { from { opacity: .72; transform: translateY(5px); } to { opacity: 1; transform: none; } }
    #main.vrcrp-page-arrive { animation: vrcrp-page-arrive 180ms cubic-bezier(.2,.7,.2,1); }
    html[data-vrcrp-reduce-transparency="true"] .app-top,
    html[data-vrcrp-reduce-transparency="true"] .dialog-panel {
      background: rgb(var(--surface)) !important; -webkit-backdrop-filter: none !important; backdrop-filter: none !important;
    }
    @media (prefers-reduced-motion: reduce) { #main.vrcrp-page-arrive { animation: none; } }
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
  let routePending = false;
  let lastPath = location.pathname;
  let entries = [location.pathname + location.search];
  let index = 0;
  let baseIndex = Number.isInteger(history.state?.idx) ? history.state.idx : 0;
  function route() {
    post({ kind: 'route', path: location.pathname, canGoBack: index > 0 && !roots.has(location.pathname), refreshable: refreshable.has(location.pathname) });
  }
  function arrive() {
    const main = document.getElementById('main');
    if (!main || matchMedia('(prefers-reduced-motion: reduce)').matches || document.documentElement.dataset.vrcrpReduceMotion === 'true') return;
    if (document.activeElement?.matches('input,textarea,[contenteditable="true"]')) return;
    if (getComputedStyle(main).animationName !== 'none') return;
    main.classList.add('vrcrp-page-arrive');
    setTimeout(() => main.classList.remove('vrcrp-page-arrive'), 220);
  }
  async function update() {
    queued = false;
    const currentGeneration = ++generation;
    const root = document.documentElement;
    if (!root || !document.head) return;
    root.dataset.vrcrpApp = 'true';
    if (!document.getElementById('vrcrp-app-surfaces')) {
      const style = document.createElement('style'); style.id = 'vrcrp-app-surfaces'; style.textContent = css; document.head.appendChild(style);
    }
    if (!ready && (document.querySelector('#root')?.innerText.trim() || document.querySelector('main,form,[role="dialog"]'))) {
      ready = true; post({ kind: 'ready' });
    }
    if (routePending) {
      routePending = false; route();
      if (lastPath !== location.pathname) arrive();
      lastPath = location.pathname;
    }
    const nav = document.querySelector('.app-bottom');
    const anchors = nav ? [...nav.querySelectorAll('a[href]')] : [];
    let model = { kind: 'navigation', visible: false };
    if (nav && anchors.length === 5 && getComputedStyle(nav).display !== 'none' && nav.getBoundingClientRect().width > 0) {
      const rect = nav.getBoundingClientRect();
      // Native views must not cover a site's modal, menu backdrop or lightbox.
      const visible = getComputedStyle(nav).visibility !== 'hidden' && !navigationBlocked(nav, rect);
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
          selected: a.getAttribute('aria-current') === 'page', frame: box(a, rect), iconFrame: svg ? box(svg, a.getBoundingClientRect()) : null, labelFrame,
          icon: svg ? await rasterIcon(svg, getComputedStyle(svg).color) : '', color: rgba(style.color), fontSize: parseFloat(style.fontSize), bold: parseInt(style.fontWeight) >= 600,
          badge: badge ? { title: badge.textContent, frame: box(badge, a.getBoundingClientRect()), color: rgba(badgeStyle.color), background: rgba(badgeStyle.backgroundColor) } : null,
        };
      }));
      if (currentGeneration !== generation || nav !== document.querySelector('.app-bottom')) return;
      let background = rgba(navStyle.backgroundColor);
      if (background[3] < .05) background = rgba(getComputedStyle(document.body).backgroundColor);
      model = { kind: 'navigation', visible, frame: box(nav), bottomPadding: parseFloat(navStyle.paddingBottom) || 0, background, items };
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
    const anchors = [...(document.querySelector('.app-bottom')?.querySelectorAll('a[href]') ?? [])];
    if (Number.isInteger(slot) && slot >= 0 && slot < anchors.length) anchors[slot].click();
  };
  window.__vrcrpBack = () => { if (index > 0 && !roots.has(location.pathname)) history.back(); };
  window.__vrcrpOpenMatches = () => {
    const link = document.querySelector('.app-bottom a[href="/matches"]');
    if (link) link.click(); else location.assign('/matches');
  };
  for (const method of ['pushState', 'replaceState']) {
    const original = history[method];
    history[method] = function (...args) {
      const result = Reflect.apply(original, this, args);
      const path = location.pathname + location.search;
      if (method === 'pushState') { entries.splice(index + 1); entries.push(path); index++; }
      else { entries[index] = path; if (index === 0 && Number.isInteger(history.state?.idx)) baseIndex = history.state.idx; }
      routePending = true; schedule();
      return result;
    };
  }
  window.addEventListener('popstate', () => {
    const path = location.pathname + location.search;
    const target = Number.isInteger(history.state?.idx) ? history.state.idx - baseIndex : -1;
    index = target >= 0 && target < entries.length && entries[target] === path ? target : Math.max(0, entries.lastIndexOf(path));
    routePending = true; schedule();
  });
  document.addEventListener('click', event => {
    if (!event.isTrusted) return;
    const el = event.target instanceof Element ? event.target : event.target.parentElement;
    const control = el?.closest('button,[role="button"],.app-bottom a');
    if (control && !control.matches(':disabled,[aria-disabled="true"]')) post({ kind: 'haptic', style: control.closest('.app-bottom') ? 'selection' : 'light' });
  }, { passive: true, capture: true });
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
  }).observe(document, { subtree: true, childList: true, attributes: true, characterData: true, attributeFilter: ['class', 'style', 'aria-current', 'open', 'data-preset', 'data-theme'] });
  window.addEventListener('resize', schedule);
  window.addEventListener('scroll', schedule, { passive: true });
  document.addEventListener('focusin', schedule);
  routePending = true; schedule();
})();
