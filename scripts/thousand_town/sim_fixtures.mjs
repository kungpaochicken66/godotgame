#!/usr/bin/env node
// Thousand Town simulation fixtures (design/thousand-town.md, sections 2 and 11).
//
// Runs upstream's own pure resident, clock, lighting, transit and event code in Node and writes what it
// produces as deterministic JSON. game/tests/thousand_sim_tests.gd then proves that the GDScript port
// (game/scripts/core/thousand_sim.gd, thousand_sim_data.gd, thousand_clock.gd) gives the same answers.
//
//   node scripts/thousand_town/sim_fixtures.mjs           write game/tests/thousand/fixtures/*.json
//   node scripts/thousand_town/sim_fixtures.mjs --check   regenerate in memory and compare with the files
//
// Upstream is the pinned, read-only copy of https://github.com/YiHuiShiBY/thousand-town (CC BY 4.0). It is
// untrusted data: this script never runs from inside that folder, checks the pinned commit, and refuses to
// load any upstream file whose SHA-256 is not in FILES below (transitive requires included).
//
// Output rules: object keys sorted, integers as integers, every other number rounded to 9 decimals with
// trailing zeros removed, no timestamps. Two runs give byte-identical files.
import crypto from 'node:crypto';
import fs from 'node:fs';
import Module, { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const UPSTREAM = path.join(ROOT, 'build', 'dual-host', 'thousand-town', 'upstream', 'thousand-town-1332ef2');
const OUT = path.join(ROOT, 'game', 'tests', 'thousand', 'fixtures');
const COMMIT = '1332ef29d6208a4192bf7400e0085033fd773a3c';
const SEED = 20260818;

// Every upstream file this script may load, with its SHA-256 at the pinned commit.
const FILES = {
  'city-airship.js': '3bcb52175bd693ae46a64b95dd3c9e7bab9c06cc58b01b56ed53f51864530a99',
  'city-facilities.js': '07e55c0fb704a7c874a703cf0d8b12d94caf88244d75e86a1a30c0c3cb2a42e0',
  'city-fireworks.js': '69aa5e64accd40a5160b5c59b56e8c2dfff165a9ffd8ff4814ae297228a787e3',
  'city-fountain.js': '57704231d5f2cbdad33c9199d3fcdadf6b71df548bec6055dbcb324be23baa7a',
  'city-helipad.js': 'bc887166dc31eceadad4f5f9ca1fc10d6afcec869aeee7c094588e98ef701dfc',
  'city-housing-plan.js': 'b91f11b91ffcdd50adefb1667dd71b1e0543b3b1cf2eb560bf041de9a42e0572',
  'city-layout.js': 'f11e213ee0208079fe864d8d7f75131f83181b45ec0647bb0952e85a917914b7',
  'city-life-ext/daily-clock.js': '2fb00b60c2225378242d2090ee615f953a76c340a4dea41a923b79090d07e56d',
  'city-life-ext/lighting.js': '20e2753382a11ae131699dd8f3a5b736e1e9517f769646cb11cf973285cd0021',
  'city-life-ext/plan-snapshot.js': 'fe480cab982270c62489ea710ce0c7b7880da804397f19f15c10ea99a3bb091a',
  'city-life-ext/resident-name.js': '2ecfe3e6f3f0561dec6c7a896bb072b1b8a637ab6a1aa07222391ae26cf60eee',
  'city-life-ext/resident-plan.js': '42fce8719360d85b97719f1f2669fb4c2e0919943b095445f0c6e444ab30368b',
  'city-life-ext/resident-schedule.js': '91562ffd8230ab7f294e298ed0161365ebc43dd0d10883ba5016328c60784ded',
  'city-life-ext/resident-state.js': '46187a6ced130d54a88980100e321a6f87ed0264c85cdf35cbfc6cf7562d80f5',
  'city-life-ext/resident.js': '3ef6e23b15b775cf8554e1af1686e3e1f1da1e7c4c823f16b18c83d2158f755e',
  'city-life-ext/town-view.js': 'c19532bc68ac90c1c27eff975c159849ca41a3dcf35a1f05d4d0afa019af8dc2',
  'city-materials.js': '09a4e885687ae9d4bde7147eb3c4bc8440b72debef4ae6d5d58ca2e34048151d',
  'city-model.js': '98a9b5f0c591ef375c54ebd8ee9a32759251994038ffe7847529f1047990e3a9',
  'city-places.js': '84fe8a2a308b92326071656a138e89f387964b6380e0bd287d73dc19faadd03f',
  'city-random.js': '441e8419826de45ee183127ef41108c944114d5aa477988ca85b05f69d393aeb',
  'city-transit-motion.js': '32ea84d03640a3ced96d7e92caf15ae23e2acbdda16e2d7cdc3827ac3ba214ab',
  'city-waterfront.js': '6238fdb8612ab1f55a5d28e327a506cbf1f6b45b673724b809558f0495d88480',
};

const DAYS = [1, 6, 7, 42];
const SWEEP_DAYS = [2, 3, 4, 5, 8, 13, 14, 20, 21, 27, 28, 35, 100, 365];
const SAMPLE_DAYS = [1, 6, 7];
const SAMPLE_MINUTES = [180, 450, 720, 1020, 1260];
const UPSTREAM_SPM = 0.625;

function fail(message) {
  console.error('sim_fixtures: ' + message);
  process.exit(1);
}

function sha(algorithm, ...chunks) {
  const hash = crypto.createHash(algorithm);
  chunks.forEach((chunk) => hash.update(chunk));
  return hash.digest('hex');
}

// ---------------------------------------------------------------- upstream verification

// The blob ids git recorded for the checked-out tree (index format 2), read without running git.
function gitIndex() {
  const data = fs.readFileSync(path.join(UPSTREAM, '.git', 'index'));
  if (data.toString('latin1', 0, 4) !== 'DIRC' || data.readUInt32BE(4) !== 2) fail('unsupported git index');
  const count = data.readUInt32BE(8);
  const entries = new Map();
  let at = 12;
  for (let i = 0; i < count; i++) {
    const blob = data.toString('hex', at + 40, at + 60);
    const nameLength = data.readUInt16BE(at + 60) & 0xfff;
    if (nameLength === 0xfff) fail('git index path too long');
    entries.set(data.toString('utf8', at + 62, at + 62 + nameLength), blob);
    at += Math.ceil((62 + nameLength + 1) / 8) * 8;
  }
  return entries;
}

function verifyUpstream() {
  const head = fs.readFileSync(path.join(UPSTREAM, '.git', 'HEAD'), 'utf8').trim();
  if (head !== COMMIT) fail('upstream HEAD is ' + head + ', expected the pinned commit ' + COMMIT);
  const index = gitIndex();
  const record = {};
  for (const name of Object.keys(FILES).sort()) {
    const bytes = fs.readFileSync(path.join(UPSTREAM, name));
    const sha256 = sha('sha256', bytes);
    if (sha256 !== FILES[name]) fail('SHA-256 mismatch for upstream ' + name);
    const blob = sha('sha1', 'blob ' + bytes.length + '\0', bytes);
    if (index.get(name) !== blob) fail('upstream ' + name + ' differs from the blob git checked out');
    record[name] = { bytes: bytes.length, gitBlob: blob, sha256 };
  }
  return record;
}

// Refuse to compile any file of the upstream copy that is not in FILES with the recorded hash. This also
// covers the files upstream modules require themselves.
function guardRequires() {
  const original = Module._extensions['.js'];
  Module._extensions['.js'] = function (module, filename) {
    const relative = path.relative(UPSTREAM, filename);
    if (!relative.startsWith('..') && !path.isAbsolute(relative)) {
      const name = relative.split(path.sep).join('/');
      if (!FILES[name] || sha('sha256', fs.readFileSync(filename)) !== FILES[name]) {
        throw new Error('unverified upstream file ' + name);
      }
    }
    return original(module, filename);
  };
}

// ---------------------------------------------------------------- deterministic JSON

function num(value) {
  if (!Number.isFinite(value)) throw new Error('non-finite number in a fixture');
  if (Number.isInteger(value)) return value === 0 ? '0' : String(value);
  let text = value.toFixed(9);
  if (text.indexOf('.') >= 0) text = text.replace(/0+$/, '').replace(/\.$/, '');
  return text === '-0' ? '0' : text;
}

function flat(value) {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'number') return num(value);
  if (typeof value === 'boolean' || typeof value === 'string') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(flat).join(',') + ']';
  return '{' + Object.keys(value).sort().map((key) => JSON.stringify(key) + ':' + flat(value[key])).join(',') + '}';
}

// Containers open onto one line per element down to `depth`, so diffs stay readable.
function pretty(value, depth) {
  if (depth <= 0 || value === null || typeof value !== 'object') return flat(value);
  if (Array.isArray(value)) {
    if (!value.length) return '[]';
    return '[\n' + value.map((item) => pretty(item, depth - 1)).join(',\n') + '\n]';
  }
  const keys = Object.keys(value).sort();
  if (!keys.length) return '{}';
  return '{\n' + keys.map((key) => JSON.stringify(key) + ':' + pretty(value[key], depth - 1)).join(',\n') + '\n}';
}

// ---------------------------------------------------------------- load upstream

const upstreamRecord = verifyUpstream();
guardRequires();
const require = createRequire(import.meta.url);
const load = (name) => require(path.join(UPSTREAM, name));

const CityRandom = load('city-random.js');
const CityModel = load('city-model.js');
const CityFacilities = load('city-facilities.js');
const CityPlaces = load('city-places.js');
const CityHousingPlan = load('city-housing-plan.js');
const CityLayout = load('city-layout.js');
const CityWaterfront = load('city-waterfront.js');
const Clock = load('city-life-ext/daily-clock.js');
const Residents = load('city-life-ext/resident.js');
const Names = load('city-life-ext/resident-name.js');
const Schedules = load('city-life-ext/resident-schedule.js');
const Plans = load('city-life-ext/resident-plan.js');
const State = load('city-life-ext/resident-state.js');
const Snapshots = load('city-life-ext/plan-snapshot.js');
const TownView = load('city-life-ext/town-view.js');
const Lighting = load('city-life-ext/lighting.js');
const Materials = load('city-materials.js');
const Transit = load('city-transit-motion.js');
const Fireworks = load('city-fireworks.js');
const Fountain = load('city-fountain.js');
const Helipad = load('city-helipad.js');
const Airship = load('city-airship.js');

// The town exactly as sketch.js builds it (sketch.js:11, 133-139 and 218-219).
const SETTINGS = { seed: SEED, density: 0.8, skyline: 1, speed: 1, daySpeed: 1, dreamLight: 0.7, stone: '#ece5d9',
  glass: '#8fa9ab', ground: '#d8d2c7', blenderModel: true, housingBlenderModel: true, playground: true, housing: true };
const city = CityLayout.apply(CityHousingPlan.decorate(CityPlaces.decorate(CityFacilities.decorate(
  CityModel.createCity(SETTINGS.seed, SETTINGS))), SETTINGS), CityLayout.identity());
city.waterfront = { stalls: CityWaterfront.plan(city), civic: CityWaterfront.civicSite(city) };
const town = Residents.create({ seed: city.seed, roster: [] });
const bindings = TownView.bindMap(city, town.buildings);
const residentIndex = new Map(town.residents.map((r, i) => [r.id, i]));
const buildingIds = town.buildings.map((b) => b.id);

const snapshots = new Map();
function snapshot(day) {
  if (!snapshots.has(day)) {
    const plans = town.residents.map((r) => Plans.buildDay(r, day, { seed: town.seed, town: town.town }));
    snapshots.set(day, { plans, snapshot: Snapshots.capture(town.seed, day, plans) });
  }
  return snapshots.get(day);
}

const files = {};

// ---------------------------------------------------------------- rng.json

{
  const seeds = [0, 1, 42, SEED, 0x6f13ab79, 0x7fffffff, 0x80000000, 0xffffffff, (SEED ^ 0x6f13ab79) >>> 0];
  const keys = ['', 'a', 'street', SEED + ':office-037:1', SEED + ':office-037:42', SEED + ':retiree-190:7',
    SEED + ':preschooler-001:habit', SEED + ':medical-nurse-030:habit', '0:x:0', 'The quick brown fox',
    '千人小镇', 'h-courtyard', 'c-night-market'];
  files['rng.json'] = {
    mulberry32: seeds.map((seed) => {
      const rng = CityRandom.randomGenerator(seed);
      const outputs = [];
      // The generator returns uint32 / 2^32, so the numerator is recovered exactly.
      for (let i = 0; i < 64; i++) outputs.push(rng() * 4294967296);
      return { outputs, seed };
    }),
    hash32: keys.map((key) => ({ hash: Plans.hash32(key), key })),
    variants: ['office-037', 'retiree-001', 'student-u-070', 'worker-105', 'senior-060'].map((id) => (
      { id, variant: Plans.variantOf(String(SEED), { id }) })),
    dayRng: [['office-037', 1], ['retiree-190', 7], ['clerk-022', 42]].map(([id, day]) => {
      const rng = Plans.dayRng(String(SEED), id, day);
      return { day, id, outputs: [rng(), rng(), rng(), rng()].map((v) => v * 4294967296) };
    }),
  };
}

// ---------------------------------------------------------------- clock.json

{
  const seconds = [-5, 0, 0.3, 0.624, 0.625, 1, 224.9, 225, 449.99, 450, 899.999, 900, 901.3, 3600, 37799.5, 123456.789];
  const days = [];
  for (let day = 1; day <= 50; day++) {
    days.push([day, Clock.dow(day), Clock.dayType(day), Clock.isWeekend(day), Clock.weekIndex(day)]);
  }
  const minutes = [];
  for (let m = -90; m <= 1530; m += 15) minutes.push([m, Clock.daylight(m), Clock.isNight(m), Clock.format(m)]);
  [329.5, 330.25, 419.9, 1110.5, 1169.75, 1439.999].forEach((m) => (
    minutes.push([m, Clock.daylight(m), Clock.isNight(m), Clock.format(m)])));
  files['clock.json'] = {
    constants: { anchors: Clock.ANCHORS, daysPerWeek: Clock.DAYS_PER_WEEK, dayTypes: Clock.DAY_TYPES,
      minutesPerDay: Clock.MINUTES_PER_DAY, secondsPerSimMinute: Clock.SECONDS_PER_SIM_MINUTE, shifts: Clock.SHIFTS },
    elapsedColumns: ['seconds', 'totalMinutes', 'minuteOfDay', 'dayIndex'],
    elapsed: seconds.map((s) => [s, Clock.totalMinutes(s), Clock.minuteOfDay(s), Clock.dayIndex(s)]),
    dayColumns: ['day', 'dow', 'dayType', 'isWeekend', 'weekIndex'],
    days,
    minuteColumns: ['minute', 'daylight', 'isNight', 'format'],
    minutes,
    shiftWindow: [-1, 0, 1, 2, 3, 1.7].map((i) => [i, Clock.shiftWindow(i).start, Clock.shiftWindow(i).end]),
  };
}

// ---------------------------------------------------------------- roster.json

{
  const locate = (id) => bindings.locate(id).map((at) => [at.mapId, at.x, at.z, at.w, at.d, at.floors, at.height]);
  files['roster.json'] = {
    seed: town.seed,
    stats: town.stats,
    kinds: town.town.kinds,
    buildingColumns: ['id', 'kind', 'type', 'capacity', 'open', 'annexOf', 'annexClinic', 'podium', 'waterfront',
      'workers', 'residents', 'venueUse'],
    buildings: town.buildings.map((b) => [b.id, b.kind, b.type || null, b.capacity, b.open || 'daily',
      b.annexOf || null, b.annexClinic || null, !!b.podium, !!b.waterfront, b.workers, b.residents.length,
      b.venueUse || 0]),
    // Reference only (upstream units, 1 unit = 0.5 m): where town-view.js binds each ledger building on the map.
    bindingColumns: ['mapId', 'x', 'z', 'w', 'd', 'floors', 'height'],
    bindings: Object.fromEntries(buildingIds.map((id) => [id, locate(id)])),
    residentColumns: ['id', 'ordinal', 'role', 'age', 'gender', 'birthMonth', 'pace100', 'sociability100', 'home',
      'workplace', 'workplaceKind', 'shiftIndex', 'clinic', 'dutyPost', 'venuePolicy', 'leisureVenue', 'variant',
      'name', 'pinyin'],
    residents: town.residents.map((r) => [r.id, r.ordinal, r.role, r.age, r.gender, r.birthMonth,
      Math.round(r.traits.pace * 100), Math.round(r.traits.sociability * 100), r.home, r.workplace, r.workplaceKind,
      r.shiftIndex === null ? -1 : r.shiftIndex, r.clinic, r.dutyPost, r.venuePolicy,
      r.leisureVenue === undefined ? null : r.leisureVenue, Plans.variantOf(String(town.seed), r), r.name, r.pinyin]),
  };
}

// ---------------------------------------------------------------- templates.json and plans.json

const STATES = Schedules.STATES.slice();
const TOKENS = ['AMUSEMENT', 'ANNEX', 'BANK', 'CIVIC', 'CLINIC', 'DUTY', 'HOME', 'MALL', 'MARKET', 'NIGHT', 'PARK',
  'PLAZA', 'POST', 'SCHOOL', 'STREET', 'WORK'];
const LOCATIONS = buildingIds.concat(['street']);

function indexOf(list, value, what) {
  const index = list.indexOf(value);
  if (index < 0) throw new Error('unknown ' + what + ' ' + value);
  return index;
}

{
  // Every schedule template for every habit draw 0..99, in a fixed list of contexts. One FNV-1a hash per
  // (template, context) over all 100 variants keeps the file small and still pins every branch.
  const shifts = { none: undefined, early: Clock.SHIFTS[0], mid: Clock.SHIFTS[1], night: Clock.SHIFTS[2] };
  const contexts = [];
  Object.keys(shifts).forEach((shift) => contexts.push({ shift, ordinal: 1, role: 'office', dayType: 'weekday', halfDay: false }));
  ['none', 'early'].forEach((shift) => ['weekday', 'saturday'].forEach((dayType) => (
    contexts.push({ shift, ordinal: 2, role: 'officer', dayType, halfDay: false }))));
  ['preschooler', 'student-p', 'student-m', 'student-u', 'office'].forEach((role) => ['saturday', 'sunday'].forEach((dayType) => (
    contexts.push({ shift: 'none', ordinal: 3, role, dayType, halfDay: false }))));
  ['weekday', 'saturday'].forEach((dayType) => contexts.push({ shift: 'none', ordinal: 1, role: 'clerk', dayType, halfDay: true }));
  const substates = new Set(['']);
  const evaluate = (name, context, variant) => Schedules.TEMPLATES[name]({ shift: shifts[context.shift],
    variant, ordinal: context.ordinal, role: context.role, dayType: context.dayType, halfDay: context.halfDay });
  const names = Object.keys(Schedules.TEMPLATES);
  names.forEach((name) => contexts.forEach((context) => {
    for (let v = 0; v < 100; v++) evaluate(name, context, v).forEach((s) => substates.add(s.substate || ''));
  }));
  const SUBSTATES = Array.from(substates).sort();
  const hashes = {};
  const samples = {};
  names.forEach((name) => {
    hashes[name] = contexts.map((context) => {
      let h = 0x811c9dc5;
      const mix = (value) => { h = Math.imul(h ^ value, 0x01000193) >>> 0; };
      for (let v = 0; v < 100; v++) {
        evaluate(name, context, v).forEach((s) => {
          mix(s.start); mix(s.end); mix(indexOf(STATES, s.state, 'state'));
          mix(indexOf(TOKENS, s.location, 'token')); mix(indexOf(SUBSTATES, s.substate || '', 'substate'));
        });
        mix(0xffff);
      }
      return h;
    });
    // One readable sample per template (variant 0, first context), to locate a mismatch quickly.
    samples[name] = evaluate(name, contexts[0], 0).flatMap((s) => [s.start, s.end, indexOf(STATES, s.state, 'state'),
      indexOf(TOKENS, s.location, 'token'), indexOf(SUBSTATES, s.substate || '', 'substate')]);
  });
  files['templates.json'] = { contexts, hashes, roleTemplate: Schedules.ROLE_TEMPLATE, samples, states: STATES,
    substates: SUBSTATES, tokens: TOKENS, variantTemplates: Schedules.VARIANT_TEMPLATES };
}

const PLAN_SUBSTATES = (() => {
  const seen = new Set(['']);
  DAYS.forEach((day) => snapshot(day).plans.forEach((plan) => plan.segments.forEach((s) => seen.add(s.substate || ''))));
  return Array.from(seen).sort();
})();

{
  const days = {};
  DAYS.forEach((day) => {
    const plans = snapshot(day).plans;
    const invalid = [];
    plans.forEach((plan) => { const check = Plans.validate(plan); if (!check.ok) invalid.push([plan.owner, check.problems]); });
    days[day] = {
      dayType: Clock.dayType(day),
      duty: plans.map((plan) => (plan.dutyPost ? indexOf(LOCATIONS, plan.dutyPost, 'location') : -1)),
      dutyPosts: Plans.dutyPosts(town.town, Clock.dayType(day)),
      invalid,
      stateChanges: plans.map((plan) => State.stateChanges(plan)),
      // Per resident in roster order: start, end, state, location, substate (indices into the lists above), repeated.
      segments: plans.map((plan) => plan.segments.flatMap((s) => [s.start, s.end, indexOf(STATES, s.state, 'state'),
        indexOf(LOCATIONS, s.location, 'location'), indexOf(PLAN_SUBSTATES, s.substate || '', 'substate')])),
    };
  });
  // More days by hash only (weekdays, the next weekends, far days): one FNV-1a hash over every segment of
  // every resident, with the substate mixed in as the hash32 of its name so no table is needed.
  const hashes = {};
  DAYS.concat(SWEEP_DAYS).forEach((day) => {
    const plans = town.residents.map((r) => Plans.buildDay(r, day, { seed: town.seed, town: town.town }));
    let h = 0x811c9dc5;
    const mix = (value) => { h = Math.imul(h ^ value, 0x01000193) >>> 0; };
    plans.forEach((plan) => {
      plan.segments.forEach((s) => {
        mix(s.start); mix(s.end); mix(indexOf(STATES, s.state, 'state'));
        mix(indexOf(LOCATIONS, s.location, 'location')); mix(Plans.hash32(s.substate || ''));
      });
      mix(plan.dutyPost ? indexOf(LOCATIONS, plan.dutyPost, 'location') : 0xffff);
    });
    hashes[day] = h;
  });
  files['plans.json'] = { days, hashes, locations: LOCATIONS, seed: town.seed, states: STATES, substates: PLAN_SUBSTATES };
}

// ---------------------------------------------------------------- occupancy.json

function lightingRow(entry) {
  // maxPanes is Infinity unless the building is shut with somebody on duty inside; -1 stands for "no limit".
  return [entry.open, entry.occupied, entry.awake, entry.room, entry.maxPanes === Infinity ? -1 : entry.maxPanes,
    entry.entry, entry.facade, entry.decoration];
}

{
  const samples = [];
  SAMPLE_DAYS.forEach((day) => SAMPLE_MINUTES.forEach((minute) => {
    const { plans, snapshot: snap } = snapshot(day);
    const view = TownView.sample(town, snap, minute);
    const light = Lighting.sample(town.buildings, snap, minute, view);
    const occupancy = State.occupancy(plans, minute);
    samples.push({
      day,
      minute,
      night: view.night,
      occupancy: { byState: occupancy.byState, missing: occupancy.missing, perBuilding: occupancy.perBuilding, street: occupancy.street },
      // Per resident in roster order: state, location, substate, stateSince, untilMinute.
      states: plans.map((plan) => {
        const at = State.stateAt(plan, minute);
        return [indexOf(STATES, at.state, 'state'), indexOf(LOCATIONS, at.location, 'location'),
          indexOf(PLAN_SUBSTATES, at.substate || '', 'substate'), at.stateSince, at.untilMinute];
      }),
      buildings: town.buildings.map((row) => {
        const value = view.byBuilding[row.id];
        const demand = view.demand.byBuilding[row.id];
        return { awake: value.awake, byState: value.byState, doorOpen: value.doorOpen, homeCount: value.homeIds.length,
          id: row.id, lightLevel: value.lightLevel, open: value.open,
          present: value.presentIds.map((id) => residentIndex.get(id)), staff: demand.staff, visitors: demand.visitors,
          working: value.working, lighting: lightingRow(light.buildings[row.id]) };
      }),
      streetByDestination: view.demand.streetByDestination,
      outdoor: Object.fromEntries(Object.entries(view.demand.outdoorByBuilding).map(([id, v]) => [id, [v.total, v.staff, v.visitors, v.open]])),
      factors: [light.minute, light.daylight, light.lamps, light.dusk, light.windows],
    });
  }));
  // Peak concurrent occupants over day 1 in 5-minute steps (resident-state.js peakOccupancy).
  files['occupancy.json'] = { lightingColumns: ['open', 'occupied', 'awake', 'room', 'maxPanes', 'entry', 'facade', 'decoration'],
    locations: LOCATIONS, peaks: { 1: State.peakOccupancy(snapshot(1).plans, 5), 7: State.peakOccupancy(snapshot(7).plans, 5) },
    samples, states: STATES, substates: PLAN_SUBSTATES };
}

// ---------------------------------------------------------------- lighting.json

{
  const factors = [];
  const push = (m) => { const f = Lighting.factors(m); factors.push([m, f.minute, f.daylight, f.lamps, f.dusk, f.windows]); };
  for (let m = 0; m < 1440; m += 10) push(m);
  [-30, 347.5, 352.25, 366.6, 395.125, 975.5, 1001.75, 1033.3, 1112.5, 1118.875, 1155.5, 1439.5, 1500, 2880].forEach(push);
  const open = [];
  ['daily', 'weekday', 'sat-am'].forEach((policy) => [1, 5, 6, 7, 13, 14].forEach((day) => (
    [0, 479, 480, 839, 840, 1019, 1020].forEach((minute) => open.push([policy, day, minute, Lighting.isOpen(policy, day, minute)])))));
  const buildings = {};
  [1, 6].forEach((day) => {
    const { snapshot: snap } = snapshot(day);
    const rows = [];
    for (let m = 0; m < 1440; m += 10) {
      const light = Lighting.sample(town.buildings, snap, m, TownView.sample(town, snap, m));
      rows.push(town.buildings.map((row) => lightingRow(light.buildings[row.id])));
    }
    buildings[day] = rows;
  });
  // The night-owl coin (lighting.js hashId) is private; an empty town at 23:20 exposes it: a housing row
  // shows .12 exactly when its coin is below .38.
  const owlIds = buildingIds.filter((id) => id.startsWith('h-')).concat(['h-a', 'h-b', 'h-c', 'h-d', 'h-e', 'h-f',
    'h-g', 'h-h', 'block-1', 'block-2', 'block-3', 'block-4', 'block-5', 'block-6', 'block-7', 'block-8']);
  const owlRows = owlIds.map((id) => ({ id, kind: 'housing', capacity: 10 }));
  const owl = Lighting.sample(owlRows, { day: 1, plans: [] }, 1400, null);
  // The street-traffic service rule (lighting.js dispatch), also used by the station loop.
  const dispatch = [];
  ['bus', 'shuttle', 'taxi', 'police', 'car'].forEach((kind) => [0, 1, 2, 7, 14].forEach((ordinal) => {
    const row = [];
    for (let m = 0; m < 1440; m += 30) row.push(Lighting.dispatch(kind, ordinal, m));
    dispatch.push([kind, ordinal, row]);
  }));
  files['lighting.json'] = {
    buildingIds,
    buildingColumns: ['open', 'occupied', 'awake', 'room', 'maxPanes', 'entry', 'facade', 'decoration'],
    buildings,
    dispatch,
    factorColumns: ['input', 'minute', 'daylight', 'lamps', 'dusk', 'windows'],
    factors,
    open,
    owl: owlIds.map((id) => [id, owl.buildings[id].room]),
    streetFadeRun: Lighting.STREET_FADE_RUN,
  };
}

// ---------------------------------------------------------------- sky.json

{
  const rows = [];
  const push = (seconds) => {
    const minute = Clock.minuteOfDay(Math.max(0, seconds));
    const duskIn = Lighting.factors(minute).dusk; // what city-scene.js passes (state.lighting.dusk)
    const s = Materials.skyState(seconds, duskIn);
    rows.push([seconds, duskIn, s.minute, s.daylight, s.goldenHour, s.sunsetBlend, s.cloudSea, s.sunVisibility,
      s.lowSunHaze, s.sunRadius, s.moonVisibility, s.dusk, s.sunPosition.x, s.sunPosition.y, s.sunPosition.z,
      s.moonPosition.x, s.moonPosition.y, s.moonPosition.z, s.sunDirection.x, s.sunDirection.y, s.sunDirection.z,
      s.moonDirection.x, s.moonDirection.y, s.moonDirection.z, s.spaceAngle, s.cloudShift]);
  };
  for (let m = 0; m < 1440; m += 10) push(m * UPSTREAM_SPM);
  // Between whole minutes (the sky moves smoothly) and on a later day.
  [206.3, 207.11, 245.05, 300.4, 637.77, 650.01, 712.6, 725.9, 731.2, 899.99, 900 + 331 * UPSTREAM_SPM, 5 * 900 + 711.3].forEach(push);
  files['sky.json'] = {
    columns: ['seconds', 'duskIn', 'minute', 'daylight', 'goldenHour', 'sunsetBlend', 'cloudSea', 'sunVisibility',
      'lowSunHaze', 'sunRadius', 'moonVisibility', 'dusk', 'sunX', 'sunY', 'sunZ', 'moonX', 'moonY', 'moonZ',
      'sunDirX', 'sunDirY', 'sunDirZ', 'moonDirX', 'moonDirY', 'moonDirZ', 'spaceAngle', 'cloudShift'],
    radius: 500,
    rows,
    secondsPerSimMinute: UPSTREAM_SPM,
  };
}

// ---------------------------------------------------------------- transit.json

{
  // Upstream's status texts (city-transit-motion.js:66-76), keyed by code point so this file stays ASCII.
  const STATUS = {
    '候车': 'waiting',
    '停运': 'closed',
    '出站': 'departing',
    '回站': 'returning',
    '运营': 'running',
    '整备维护': 'servicing',
  };
  const plan = Transit.create(city);
  const times = [];
  for (let t = 0; t <= 1900; t += 11.7) times.push(t);
  // The timetable's edges: 06:00 (225 s), each first departure, a lap's end, 22:30 (843.75 s), 23:00 (862.5 s), midnight.
  [224.99, 225, 229.99, 230, 230.5, 231.1, 240.9, 256, 282, 308, 334, 360, 386, 370.5, 370.6, 394.5, 394.6, 590, 595,
    843.74, 843.75, 862.49, 862.5, 899.99, 900, 1125, 1130.01].forEach((t) => times.push(t));
  times.sort((a, b) => a - b);
  const samples = times.map((t) => [t, Transit.sample(plan, 0, t).map((v) => {
    if (!STATUS[v.status]) throw new Error('unknown transit status');
    return [v.x, v.z, v.y, v.localX, v.localZ, v.heading, v.localHeading, STATUS[v.status], v.moving];
  })]);
  files['transit.json'] = {
    site: { gateSide: plan.site.gateSide === undefined ? null : plan.site.gateSide, x: plan.site.x, z: plan.site.z },
    side: plan.side,
    vehicleColumns: ['id', 'x', 'z', 'bus', 'index', 'departure', 'length', 'segments'],
    vehicles: plan.vehicles.map((v) => [v.id, v.x, v.z, v.bus, v.index, v.departure, v.path.length, v.path.segments.length]),
    // The rounded path of the first bus and the last taxi: segment start points, then the final point.
    paths: [0, 6].map((i) => {
      const segments = plan.vehicles[i].path.segments;
      return { index: i, points: segments.map((s) => [s.a[0], s.a[1]]).concat([segments.at(-1).b.slice()]),
        starts: segments.map((s) => s.start) };
    }),
    sampleColumns: ['x', 'z', 'y', 'localX', 'localZ', 'heading', 'localHeading', 'status', 'moving'],
    samples,
    speed: 10,
    period: 360,
    secondsPerSimMinute: UPSTREAM_SPM,
  };
}

// ---------------------------------------------------------------- events.json

{
  const fireworksTimes = [-1, 0, 100, 712.4, 712.5, 712.6, 720, 736.49, 736.5, 750, 757.5, 784.5, 806.4, 808.5, 824.9,
    825, 830, 899.9, 900 + 712.5 + 30.25, 3 * 900 + 760.123456];
  const fireworks = fireworksTimes.map((seconds) => {
    const s = Fireworks.nightlyState(seconds);
    // townShow without a city returns only its bookkeeping, including the phase name of the 96 s show.
    return [seconds, s.enabled, s.minute, s.seconds, s.day, Fireworks.townShow(s.seconds, {}).phase];
  });
  // The 128-shell town score is private (townSchedule); nightlyShow exposes each live shell's site and
  // timing, so sweeping one show collects the whole score through upstream's public door.
  const schedule = new Map();
  const sites = Fireworks.launchSites(city);
  for (let t = 0; t < 96; t += 0.25) {
    const show = Fireworks.townShow(t, { city, seed: city.seed, festival: 1 });
    show.shells.forEach((shell) => {
      const key = shell.ordinal;
      if (!schedule.has(key)) schedule.set(key, shell);
    });
  }
  const shellRows = Array.from(schedule.values()).sort((a, b) => a.ordinal - b.ordinal);
  const shellColumns = ['ordinal', 'fireTime', 'siteId', 'shapeName', 'apexY', 'apexT', 'ascentVelocity', 'driftX',
    'driftZ', 'intensity', 'finale', 'color'];

  const fountain = [];
  for (let m = 0; m < 1440; m += 5) fountain.push([m, Fountain.dayLevel(m), Fountain.dayLevelSmooth(m), Fountain.programName(m)]);
  [-1, 324.5, 329.99, 414.2, 417.75, 422.5, 1075.1, 1083.9, 1104.5, 1113.25, 1136, 1142.6, 1265.5, 1272.25, 1314.5,
    1319.999, 1325.5, 1440, 1445.5].forEach((m) => fountain.push([m, Fountain.dayLevel(m), Fountain.dayLevelSmooth(m), Fountain.programName(m)]));

  const pad = Helipad.plan(city);
  const tower = Helipad.choose(city);
  const helicopter = [];
  const heliTimes = [];
  for (let t = 0; t <= 200; t += 1.3) heliTimes.push(t);
  [21.999, 22, 29.999, 30, 30.001, 51, 71.999, 72, 79.999, 80, 95.999, 96, 9600.5, 9651.25].forEach((t) => heliTimes.push(t));
  heliTimes.forEach((t) => {
    const s = Helipad.sample(pad, t);
    helicopter.push([t, s.phase, s.x, s.y, s.z, s.heading, s.bank, s.pitch, s.rotor, s.rotorTurns, s.parked, s.grounded]);
  });

  const route = Airship.plan(city);
  const airship = [];
  for (let t = 0; t <= 500; t += 3.7) {
    const s = Airship.sample(route, t);
    airship.push([t, s.x, s.y, s.z, s.heading, s.bank, s.pulse]);
  }
  const roof = Math.max(0, ...city.buildings.map((b) => (b.floors || 0) * (b.floorHeight || 6) + 22),
    ...city.places.map((p) => p.height || 0));

  files['events.json'] = {
    fireworks: {
      window: Fireworks.NIGHT_WINDOW,
      show: Fireworks.TOWN_SHOW,
      stateColumns: ['seconds', 'enabled', 'minute', 'showSeconds', 'day', 'phase'],
      states: fireworks,
      // Reference only (upstream units): the eight launch sites in the default town.
      sites: sites.map((site) => [site.id, site.x, site.y, site.z]),
      shellColumns,
      shells: shellRows.map((shell) => shellColumns.map((key) => (key === 'color' ? shell.color.name : shell[key]))),
    },
    fountain: { columns: ['minute', 'level', 'smooth', 'program'], program: Fountain.PROGRAM, rows: fountain },
    helicopter: {
      cycle: Helipad.CYCLE,
      tower: { d: tower.d, floors: tower.floors, id: tower.id, w: tower.w, x: tower.x, z: tower.z },
      plan: { a: pad.circuit.a, b: pad.circuit.b, cruise: pad.cruise, cx: pad.circuit.cx, cz: pad.circuit.cz,
        radius: pad.radius, roofY: pad.roofY, ux: pad.circuit.u.x, uz: pad.circuit.u.z, vx: pad.circuit.v.x,
        vz: pad.circuit.v.z, x: pad.x, z: pad.z },
      columns: ['time', 'phase', 'x', 'y', 'z', 'heading', 'bank', 'pitch', 'rotor', 'rotorTurns', 'parked', 'grounded'],
      rows: helicopter,
    },
    airship: {
      city: { extentX: city.extentX, extentZ: city.extentZ, roof },
      plan: route,
      columns: ['time', 'x', 'y', 'z', 'heading', 'bank', 'pulse'],
      rows: airship,
    },
  };
}

// ---------------------------------------------------------------- write or check

const DEPTH = { 'rng.json': 3, 'clock.json': 2, 'roster.json': 2, 'templates.json': 2, 'plans.json': 4,
  'occupancy.json': 4, 'lighting.json': 3, 'sky.json': 2, 'transit.json': 3, 'events.json': 3 };
const texts = {};
Object.keys(files).sort().forEach((name) => { texts[name] = pretty(files[name], DEPTH[name] || 2) + '\n'; });
texts['manifest.json'] = pretty({
  about: 'Fixtures produced by upstream Thousand Town code in Node; see scripts/thousand_town/sim_fixtures.mjs.',
  days: DAYS,
  fixtures: Object.fromEntries(Object.keys(texts).map((name) => (
    [name, { bytes: Buffer.byteLength(texts[name]), sha256: sha('sha256', texts[name]) }]))),
  license: 'CC BY 4.0',
  sampleDays: SAMPLE_DAYS,
  sweepDays: SWEEP_DAYS,
  sampleMinutes: SAMPLE_MINUTES,
  seed: SEED,
  settings: SETTINGS,
  upstream: { commit: COMMIT, files: upstreamRecord, repository: 'https://github.com/YiHuiShiBY/thousand-town' },
}, 3) + '\n';

// Nothing outside the verified list may have been loaded from the upstream copy.
Object.keys(require.cache).forEach((filename) => {
  const relative = path.relative(UPSTREAM, filename);
  if (!relative.startsWith('..') && !FILES[relative.split(path.sep).join('/')]) fail('unverified upstream module ' + relative);
});

if (process.argv.includes('--check')) {
  let stale = 0;
  Object.keys(texts).sort().forEach((name) => {
    const file = path.join(OUT, name);
    if (!fs.existsSync(file) || fs.readFileSync(file, 'utf8') !== texts[name]) { stale++; console.error('stale: ' + name); }
  });
  console.log('THOUSAND SIM FIXTURES: ' + Object.keys(texts).length + ' files checked, ' + stale + ' stale');
  process.exit(stale ? 1 : 0);
}

fs.mkdirSync(OUT, { recursive: true });
let total = 0;
Object.keys(texts).sort().forEach((name) => {
  fs.writeFileSync(path.join(OUT, name), texts[name]);
  total += Buffer.byteLength(texts[name]);
  console.log(name.padEnd(16) + String(Buffer.byteLength(texts[name])).padStart(9) + ' bytes  ' + sha('sha256', texts[name]).slice(0, 16));
});
console.log('THOUSAND SIM FIXTURES: ' + Object.keys(texts).length + ' files, ' + total + ' bytes, upstream ' + COMMIT.slice(0, 7));
