// The bridge between Godot (the game) and this page (the Three.js city's renderer and input surface).
// Protocol v1, specified in design/city-threejs.md "Bridge protocol". Every message is one JSON object with
// a type "t".
//
// Transports, chosen once at load:
//   webkit   inside the iOS app: window.webkit.messageHandlers.godot.postMessage(text) to Godot; Godot calls
//            window.LL.recv(object) on the page (scripts/web/web_city_bridge.gd + the WebView plugin).
//   ws       a desktop test (Mac, EC2): ?ws=<port> connects to Godot's bridge server at ws://127.0.0.1:<port>.
//   harness  ?harness=1: no Godot; js/harness.js plays Godot's side (a child, the clock, recorded states).
//   none     nothing to talk to: the city still draws, at the page's own clock.
export const PROTOCOL = 1;

export class Bridge {
  constructor() {
    this.kind = 'none';
    this.handlers = [];
    this.sent = 0;
    this.received = 0;
    this._ws = null;
    this._queue = [];
    this._harness = null;
  }

  /** Picks the transport (see the header). `params` is a URLSearchParams. */
  async open(params) {
    window.LL = window.LL || {};
    window.LL.recv = (msg) => this._deliver(typeof msg === 'string' ? JSON.parse(msg) : msg);
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.godot) {
      this.kind = 'webkit';
    } else if (params.get('ws')) {
      this.kind = 'ws';
      this._connect(Number(params.get('ws')));
    } else if (params.get('harness')) {
      this.kind = 'harness';
      const mod = await import('./harness.js');
      this._harness = new mod.Harness((msg) => this._deliver(msg), params);
    }
    return this.kind;
  }

  _connect(port) {
    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    this._ws = ws;
    ws.onopen = () => {
      for (const text of this._queue) ws.send(text);
      this._queue = [];
    };
    ws.onmessage = (ev) => this._deliver(JSON.parse(ev.data));
    ws.onclose = () => {
      this._ws = null;
      this._deliver({ t: 'link', up: false });
      setTimeout(() => this._connect(port), 1000);
    };
  }

  onMessage(fn) { this.handlers.push(fn); }

  _deliver(msg) {
    this.received++;
    for (const fn of this.handlers) {
      try {
        fn(msg);
      } catch (e) {
        console.error(e);
        this.send({ t: 'log', level: 'error', text: `${msg.t}: ${e && e.stack ? e.stack : e}` });
      }
    }
  }

  send(msg) {
    this.sent++;
    const text = JSON.stringify(msg);
    if (this.kind === 'webkit') {
      window.webkit.messageHandlers.godot.postMessage(text);
    } else if (this.kind === 'ws') {
      if (this._ws && this._ws.readyState === 1) this._ws.send(text);
      else if (this._queue.length < 200) this._queue.push(text);
    } else if (this.kind === 'harness' && this._harness) {
      this._harness.receive(msg);
    }
  }

  /** Called once a frame by main.js (the harness ticks with the page). */
  tick(dt) {
    if (this._harness) this._harness.tick(dt);
  }
}
