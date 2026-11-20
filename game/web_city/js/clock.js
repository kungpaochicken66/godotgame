// The city's clocks on the page, ported from the Godot city:
// - cityClock(): the shared city clock as this device estimates it (net/city.gd est_time, which Godot sends
//   in every frame message). Between two messages it runs on the page's own timer; it never runs backwards.
// - viewTime(): the time everything ambient is drawn at (world/city_world.gd view_time / advance_view): the
//   city clock, except while paused on this screen (frozen) and just after (it catches up at up to CATCH_UP
//   times the clock's pace, eased).
import { C, clamp, smoothstep } from './consts.js';

export class CityClock {
  constructor(now = () => performance.now() / 1000) {
    this.now = now;
    this._pktClock = 0;     // the city clock in the newest sample
    this._pktAt = -1;       // the page time it arrived
    this._floor = 0;
    this._view = 0;
    this._viewOk = false;
    this._paused = false;
  }

  /** A sample of the city clock from Godot (its est_time at the moment it sent the message). */
  sync(clock) {
    if (!(clock > 0)) return;
    this._pktClock = clock;
    this._pktAt = this.now();
  }

  hasClock() { return this._pktAt >= 0; }

  cityClock() {
    if (this._pktAt < 0) return 0;
    this._floor = Math.max(this._floor, this._pktClock + (this.now() - this._pktAt));
    return this._floor;
  }

  /** A clock that started afresh (a new city session): forget the floor. */
  reset() {
    this._floor = 0;
    this._viewOk = false;
    this._pktAt = -1;
  }

  viewTime() { return this._viewOk ? this._view : this.cityClock(); }

  isPaused() { return this._paused; }

  setPaused(on) {
    if (on === this._paused) return;
    if (!this._viewOk) {
      this._view = this.cityClock();
      this._viewOk = true;
    }
    this._paused = on;
  }

  /** One frame of `delta` real seconds (city_world.gd advance_view). */
  advance(delta) {
    const c = this.cityClock();
    if (!this._viewOk) {
      this._view = c;
      this._viewOk = true;
      return;
    }
    if (this._paused) return;
    const lag = c - this._view;
    if (lag <= 0.0005) {
      this._view = c;
      return;
    }
    const up = C.CityWorld.CATCH_UP;
    const rate = clamp(1.0 + (up - 1.0) * smoothstep(0.0, 1.5, lag), 1.15, up);
    this._view = Math.min(c, this._view + rate * delta);
  }
}
