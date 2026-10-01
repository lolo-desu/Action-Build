const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function fixture(origin = 'https://erp.sex') {
  const messages = [];
  class Socket extends EventTarget {
    constructor(url) { super(); this.url = url; }
    incoming(data) { this.dispatchEvent(new MessageEvent('message', { data })); }
  }
  const response = { ok: true, clone() { return { json: async () => ({ unreadMessages: 3 }) }; } };
  const context = { URL, Request, Reflect, Proxy, Number, JSON,
    location: { origin, host: new URL(origin).host, href: origin + '/' },
    window: { WebSocket: Socket, fetch: () => Promise.resolve(response),
      webkit: { messageHandlers: { erpNativeNotifications: { postMessage: data => messages.push(data) } } } } };
  vm.runInNewContext(fs.readFileSync(__dirname + '/../ERPStable/notifications.js', 'utf8'), context);
  return { ...context, messages, Socket };
}
const tick = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  const f = fixture();
  await f.window.fetch('/api/v1/me/counters');
  await tick();
  assert.deepEqual(f.messages.map(m => [m.unread, m.notify]), [[3, false]], 'initial unread count must not notify');
  const socket = new f.window.WebSocket('wss://erp.sex/api/v1/ws');
  socket.incoming(JSON.stringify({ type: 'counters', data: { unreadMessages: 4 } }));
  socket.incoming(JSON.stringify({ type: 'counters', data: { unreadMessages: 4 } }));
  socket.incoming(JSON.stringify({ type: 'counters', data: { unreadMessages: 0 } }));
  socket.incoming(JSON.stringify({ type: 'message.new', data: { text: 'private chat' } }));
  socket.incoming('invalid JSON');
  socket.incoming(JSON.stringify({ type: 'counters', data: { unreadMessages: -1 } }));
  assert.deepEqual(f.messages.map(m => [m.unread, m.notify]), [[3, false], [4, true], [4, false], [0, false]]);
  socket.dispatchEvent(new Event('close'));
  const reconnected = new f.window.WebSocket('wss://erp.sex/api/v1/ws');
  reconnected.incoming(JSON.stringify({ type: 'counters', data: { unreadMessages: 9 } }));
  assert.equal(f.messages.at(-1).notify, false, 'reconnect must not alert for older messages');
  const foreign = new f.window.WebSocket('wss://example.org/api/v1/ws');
  const before = f.messages.length;
  foreign.incoming(JSON.stringify({ type: 'counters', data: { unreadMessages: 100 } }));
  assert.equal(f.messages.length, before);
  assert.equal(JSON.stringify(f.messages).includes('private chat'), false);
  assert.equal(fixture('https://example.org').window.WebSocket.name, 'Socket', 'bridge only installs on the intended website');
  console.log('PASS: baseline, unread increases, deduplication, read reset, reconnect, invalid events and origin isolation');
})().catch(error => { console.error(error); process.exitCode = 1; });
