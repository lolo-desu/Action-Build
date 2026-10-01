(() => {
  'use strict';
  if (location.origin !== 'https://erp.sex' || !window.webkit?.messageHandlers?.erpNativeNotifications) return;
  let unread = null;
  function counters(data) {
    const count = data?.unreadMessages;
    if (!Number.isSafeInteger(count) || count < 0 || count > 100000) return;
    const notify = unread !== null && count > unread;
    unread = count;
    window.webkit.messageHandlers.erpNativeNotifications.postMessage({ unread: count, notify });
  }
  // Observe the website's own unread counter. Existing messages on launch and
  // outgoing messages never create alerts. No message text or credentials cross
  // the bridge, and no extra polling or server connections are created.
  const originalFetch = window.fetch;
  window.fetch = function (...args) {
    const result = Reflect.apply(originalFetch, this, args);
    let url;
    try { url = new URL(args[0] instanceof Request ? args[0].url : String(args[0]), location.href); } catch {}
    if (url?.origin === location.origin && url.pathname === '/api/v1/me/counters') {
      result.then(response => {
        if (response.ok) response.clone().json().then(value => counters(value.data ?? value)).catch(() => {});
      }).catch(() => {});
    }
    return result;
  };
  const OriginalWebSocket = window.WebSocket;
  window.WebSocket = new Proxy(OriginalWebSocket, {
    construct(target, args, newTarget) {
      const socket = Reflect.construct(target, args, newTarget);
      let url;
      try { url = new URL(String(args[0]), location.href); } catch {}
      if (url?.protocol === 'wss:' && url.host === location.host && url.pathname === '/api/v1/ws') {
        socket.addEventListener('message', event => {
          try {
            const value = JSON.parse(event.data);
            if (value.type === 'counters') counters(value.data);
          } catch {}
        });
        socket.addEventListener('close', () => { unread = null; });
      }
      return socket;
    }
  });
})();
