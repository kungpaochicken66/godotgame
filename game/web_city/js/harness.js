// ?harness=1: plays Godot's side without Godot, for working on the page alone (desktop browser, headless
// checks). It is not the game: one child with no rig (js/kids.js draws a stand-in), walking straight to a
// tapped point on the ground with no navigation; the city clock starts at ?t=<seconds> (default 600); the
// City states come from a recording of the real rules (dev/states.json, from tests/web_city/record_states.gd)
// when it is there, else an empty city. ?weather=0|1|2 starts in that weather.
export class Harness {
  constructor(deliver, params) {
    this.deliver = deliver;
    this.clock = Number(params.get('t') || 600);
    this.pos = [-26.0, 6.0];
    this.target = null;
    this.ry = 0;
    this.weather = Number(params.get('weather') || 0);
    this.since = -100;
    this.prev = [1, 0, 0];
    this.recording = null;
    this.timeline = 0;
    this.sent = false;
    fetch('dev/states.json').then((r) => (r.ok ? r.json() : null)).then((j) => { this.recording = j; }).catch(() => {});
  }

  _states() {
    let s = { time: this.clock, ferris_angle: 0, vehicles: [], occupancy: {}, riders: {}, ride: {} };
    const rec = this.recording;
    if (rec && rec.states && rec.states.length) {
      // the recording loops; its clock is shifted onto the harness clock
      const span = rec.states[rec.states.length - 1].time - rec.states[0].time;
      const tt = rec.states[0].time + ((this.clock - rec.states[0].time) % span + span) % span;
      let k = 0;
      while (k + 1 < rec.states.length && rec.states[k + 1].time <= tt) k++;
      s = { ...rec.states[k], time: this.clock - (tt - rec.states[k].time) };
    }
    s.weather = this.weather;
    s.since = this.since;
    s.prev = this.prev;
    s.weather_since = this.since;
    s.weather_prev = this.prev;
    return s;
  }

  receive(msg) {
    if (msg.t === 'tap' && Math.abs(msg.d[1]) > 1e-4) {
      const k = -msg.o[1] / msg.d[1];
      if (k > 0) this.target = [msg.o[0] + msg.d[0] * k, msg.o[2] + msg.d[2] * k];
    } else if (msg.t === 'weather') {
      this.prev = [this.weather === 0 ? 1 : 0, this.weather === 1 ? 1 : 0, this.weather === 2 ? 1 : 0];
      this.weather = msg.w;
      this.since = this.clock;
      this.deliver({ t: 'states', s: this._states() });
    }
  }

  tick(dt) {
    this.clock += dt;
    if (!this.sent) {
      this.sent = true;
      this.deliver({ t: 'hello', v: 1, me: 1, map: 'city_web', platform: 'harness', locale: 'en', strings: {} });
      this._next = 0;
    }
    if (this.target) {
      const dx = this.target[0] - this.pos[0];
      const dz = this.target[1] - this.pos[1];
      const d = Math.hypot(dx, dz);
      const step = 1.6 * dt;
      if (d <= step) {
        this.pos = this.target;
        this.target = null;
      } else {
        this.pos = [this.pos[0] + dx / d * step, this.pos[1] + dz / d * step];
        this.ry = Math.atan2(dx, dz);
      }
    }
    const c = Math.cos(this.ry);
    const s = Math.sin(this.ry);
    this.deliver({
      t: 'frame', clock: this.clock,
      me: { id: 1, level: '', pos: this.pos, riding: -1, hold: '', ctx: null },
      kids: [{ id: 1, me: true, rev: 0, anim: this.target ? 'walk' : 'idle', ride: null,
        xf: [c, 0, -s, 0, 1, 0, s, 0, c, this.pos[0], 0, this.pos[1]] }],
    });
    this._next -= dt;
    if (this._next <= 0) {
      this._next = 0.25;
      this.deliver({ t: 'states', s: this._states() });
    }
  }
}
