// SPC Studio, Brand tab. Plain JS, no build step. The form is generated from
// brand.json itself, so it covers every field without a schema to keep in step;
// the rules come from the app's own BrandConfig, through the server.
'use strict';

const $ = (id) => document.getElementById(id);
const HEX = /^#[0-9a-fA-F]{6}$/;
const state = {
  brands: [],
  slug: null,
  edits: {},    // slug -> the brand object being edited
  loaded: {},   // slug -> JSON as last read from or written to disk
  studio: {},   // slug -> studio.json
  results: {},  // slug -> {errors, warnings, frozen, changes}
  dirty: {},    // slug -> files git reports changed, awaiting an explicit overwrite
  raw: false,
  seq: 0,
  view: 'brand',
  studioEdits: {}, // slug -> studio.json being edited on the Integrations tab
};
let timer = null;

const current = () => state.edits[state.slug];
const edited = (slug) => JSON.stringify(state.edits[slug]) !== state.loaded[slug];
const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const hasObjects = (v) => Array.isArray(v) && v.some((x) => x !== null && typeof x === 'object');

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

async function api(path, body) {
  const init = body === undefined ? {} : {
    method: 'POST',
    // The custom header is what lets the server refuse writes from any other page.
    headers: { 'content-type': 'application/json', 'x-studio': '1' },
    body: JSON.stringify(body),
  };
  const res = await fetch(path, init);
  return { status: res.status, data: await res.json() };
}

function setAt(obj, path, value) {
  const keys = path.split('.');
  const last = keys.pop();
  keys.reduce((o, k) => o[k], obj)[last] = value;
}

// ---- loading ---------------------------------------------------------------

async function load(slug) {
  const { data } = await api(`/api/brands/${slug}`);
  state.edits[slug] = data.brand;
  state.loaded[slug] = JSON.stringify(data.brand);
  state.studio[slug] = data.studio;
  delete state.studioEdits[slug];
  state.results[slug] = data;
}

async function boot() {
  state.brands = (await api('/api/brands')).data;
  await Promise.all(state.brands.map((b) => load(b.slug)));
  const wanted = location.hash.slice(1);
  // "+ New brand" pressed while the brands were loading: stay there. select()
  // turns the wizard back into the Brand tab, which swallowed that first click.
  const pressedNew = state.view === 'wizard';
  select(state.brands.some((b) => b.slug === wanted) ? wanted : state.brands[0].slug);
  if (pressedNew) showView('wizard');
}

/// After a new brand is created: its folder is now a brand like the others.
async function reloadBrands(slug) {
  state.brands = (await api('/api/brands')).data;
  await load(slug);
  state.view = 'brand';
  select(slug);
}

function select(slug) {
  state.slug = slug;
  history.replaceState(null, '', `#${slug}`);
  renderRail();
  renderHead();
  renderProof();
  if (state.raw) $('raw-text').value = JSON.stringify(current(), null, 2);
  else renderForm();
  renderBrandIntake();
  renderResult();
  showView(state.view === 'wizard' ? 'brand' : state.view);
}

/// One line per page: its name, what it is for, and the page after it.
const GUIDE = {
  wizard: ['New brand', 'Start from a name, a logo and colours, or drop the client intake. One Apply writes the brand folder and every generated file.'],
  brand: ['Brand', 'Everything the app reads for this brand. Clear the Problems list, press Apply, then commit the files it wrote.', 'assets'],
  assets: ['Assets', 'Logos, the intro, the card background and the pack images. Drop a file on its slot to preview it; nothing is written until you press Save.', 'integrations'],
  integrations: ['Integrations', 'Values created in the Google, Apple, Play and Stripe consoles. Get it opens the right page and its steps; paste the value back, then Apply writes it.', 'backend'],
  backend: ['Backend', 'The DEV backend, then PROD. Check probes it from this PC; the checker report comes from the server. Go phase 2 unlocks test builds, and Go prod points the app at PROD.', 'build'],
  build: ['Build', 'Validate, build for test on DEV, then record Pass, Fail or Skip for this commit. Build release needs that result, a clean tree, the upload key and Go prod.', 'store'],
  store: ['Store', "The Play listing's graphics, made from this brand's files, and phone screenshots captured from the emulator. Everything goes to dist/; you upload it in Play Console."],
  logs: ['Logs', "Each job's output, with secrets masked. A failed job names the incident it matched; Solve shows its known fix, similar cases and the bundle for Claude."],
  doctor: ['Doctor', 'This machine: Flutter, the Android SDK and NDK, the emulator and the signing keys. Nothing is installed until you press its button.'],
};

function renderGuide(view) {
  const [name, text, next] = GUIDE[view] ?? [];
  const line = $('guideline');
  line.hidden = !name;
  if (!name) return;
  const parts = [el('strong', '', name), el('span', '', text)];
  if (next) {
    const go = el('button', 'ghost next', `Next: ${GUIDE[next][0]}`);
    go.type = 'button';
    go.onclick = () => showView(next);
    parts.push(go);
  }
  line.replaceChildren(...parts);
}

/// A tab or the New brand page; the side panel follows: problems and diffs
/// for the Brand tab, the jobs for Build, Logs and Doctor, a plan otherwise.
function showView(view) {
  state.view = view;
  renderGuide(view);
  const jobsSide = ['build', 'logs', 'doctor'].includes(view);
  for (const v of ['brand', 'assets', 'integrations', 'backend', 'wizard', 'build', 'store', 'logs', 'doctor']) $(`view-${v}`).hidden = v !== view;
  // On New brand there is no brand yet: its tabs are off, rather than showing the last one picked.
  const noBrand = view === 'wizard';
  $('tabs-hint').hidden = !noBrand;
  document.querySelectorAll('.tab[data-view]').forEach((t) => {
    const brandTab = !['logs', 'doctor'].includes(t.dataset.view);
    t.disabled = noBrand && brandTab;
    t.title = t.disabled ? 'Pick a brand in the list first' : '';
    t.classList.toggle('is-active', t.dataset.view === view);
    if (t.dataset.view === view) t.setAttribute('aria-current', 'page');
    else t.removeAttribute('aria-current');
  });
  $('side-brand').hidden = view !== 'brand';
  $('side-plan').hidden = view === 'brand' || jobsSide;
  $('side-jobs').hidden = !jobsSide;
  // Logs and Doctor are the machine's, not a brand's.
  $('proof').hidden = ['wizard', 'logs', 'doctor'].includes(view);
  $('new-brand').classList.toggle('is-active', view === 'wizard');
  if (view === 'assets') renderAssets();
  if (view === 'integrations') renderIntegrations();
  if (view === 'backend') renderBackend();
  if (view === 'wizard') renderWizard();
  if (view === 'build') renderBuild();
  if (view === 'store') renderStore();
  if (view === 'logs') renderLogs();
  if (view === 'doctor') renderDoctor();
  if (jobsSide) { renderJobsSide(); refreshJobs(); refreshEarlier(); }
}

// ---- editing ---------------------------------------------------------------

function edit(path, value) {
  setAt(current(), path, value);
  afterEdit();
}

function afterEdit() {
  renderHead();
  renderProof();
  renderRail();
  clearTimeout(timer);
  timer = setTimeout(preview, 250);
}

async function preview() {
  const slug = state.slug;
  const seq = ++state.seq;
  const { data } = await api(`/api/brands/${slug}/preview`, state.edits[slug]);
  if (seq !== state.seq) return; // a newer edit is already on its way
  state.results[slug] = data;
  renderRail();
  if (slug === state.slug) renderResult();
}

async function apply(acceptDirty = []) {
  const slug = state.slug;
  $('apply').disabled = true;
  status('');
  const { status: code, data } = await api(`/api/brands/${slug}/apply`, {
    brand: state.edits[slug],
    acceptDirty,
  });
  if (code === 409) {
    state.dirty[slug] = data.dirty;
    renderResult();
    return;
  }
  if (code !== 200) {
    status(data.refused || data.error, true);
    renderResult();
    return;
  }
  state.loaded[slug] = JSON.stringify(state.edits[slug]);
  delete state.dirty[slug];
  status(`Wrote ${data.written.length} file${data.written.length === 1 ? '' : 's'}. Review and commit when ready.`);
  renderHead();
  await preview();
}

function status(text, isError = false) {
  $('status').textContent = text;
  $('status').style.color = isError ? 'var(--err)' : '';
}

// ---- rendering -------------------------------------------------------------

function renderRail() {
  const list = $('brands');
  list.replaceChildren(...state.brands.map(({ slug, name }) => {
    const r = state.results[slug];
    const level = !r ? '' : r.errors.length || r.frozen.length ? 'err' : r.warnings.length ? 'warn' : 'ok';
    const b = el('button');
    if (slug === state.slug) b.setAttribute('aria-current', 'true');
    b.append(el('span', `dot ${level}`), el('span', '', state.edits[slug]?.name ?? name));
    const sub = el('span', 'slug', slug);
    if (state.edits[slug] && edited(slug)) sub.append(el('span', 'edited', ' · edited'));
    b.append(sub);
    b.onclick = () => select(slug);
    const li = el('li');
    li.append(b);
    return li;
  }));
}

function renderHead() {
  $('title').textContent = current().name ?? state.slug;
  $('revert').disabled = !edited(state.slug);
}

function luminance(hex) {
  const [r, g, b] = [1, 3, 5]
    .map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

function renderProof() {
  const brand = current();
  const colors = isObject(brand.colors) ? brand.colors : {};
  const launch = brand.logo?.introBackground ?? colors.surface;
  const swatches = [...Object.entries(colors), ['launch', launch]].filter(([, v]) => HEX.test(v ?? ''));
  $('proof').replaceChildren(...swatches.map(([role, hex]) => {
    const s = el('div', 'swatch');
    s.style.backgroundColor = hex;
    s.style.color = luminance(hex) > 0.4 ? '#111315' : '#e9e5db';
    s.title = `${role} ${hex}`;
    s.append(el('span', '', role), el('span', '', hex));
    return s;
  }));
}

function renderForm() {
  const brand = current();
  const nested = (v) => isObject(v) || hasObjects(v);
  const top = Object.entries(brand).filter(([, v]) => !nested(v));
  $('form').replaceChildren(
    section('', 'identity', top.map(([k, v]) => field(k, k, v)), true),
    ...Object.entries(brand).filter(([, v]) => nested(v)).map(([k, v]) => section(k, k, children(k, v), true)),
  );
}

function children(path, value) {
  return Object.entries(value).map(([k, v]) => {
    const p = `${path}.${k}`;
    return isObject(v) || hasObjects(v) ? section(p, k, children(p, v), false) : field(p, k, v);
  });
}

function section(path, title, kids, open) {
  const d = el('details');
  d.open = open;
  if (path) d.dataset.path = path;
  const group = el('div', 'group');
  group.append(...kids);
  d.append(el('summary', '', title), group);
  return d;
}

/// One line per brand.json field, shown while the field has focus. A key ending
/// in '.' covers a whole map (tagline.<locale>, visuals.packImages.<region>).
const HINTS = {
  slug: 'The folder name under brands/. It cannot change here.',
  name: 'The brand as people read it.',
  domain: "The brand's web domain, without https://.",
  'tagline.': 'The line under the logo, one per language.',
  'colors.primary': 'Anchor colour: strong text, dark fills, bars.',
  'colors.accent': 'Symbol, positive states, active elements.',
  'colors.surface': 'Tinted brand background, and the launch window unless logo.introBackground is set.',
  'colors.cta': 'Call-to-action fill. It needs strong contrast against primary.',
  'colors.ctaText': 'Text on a cta fill. The chip above checks it against cta.',
  'theme.shop.': 'The shop screens: Store, a destination and its packs, My eSIMs. A missing key keeps the default.',
  'theme.premium.': 'The premium block. A missing key keeps the default.',
  'logo.mark': 'Square logo in assets/, the source of every app icon.',
  'logo.full': 'Logo with the name, for light backgrounds.',
  'logo.fullInverse': 'Logo with the name, for dark backgrounds. Without it, logo.full is used, with a warning.',
  'logo.intro': 'Short animation played once at launch. It must have no audio track.',
  'logo.introBackground': 'Colour around the intro and of the native launch window. Without it, colors.surface.',
  'logo.iconBackground': 'Launcher icon background, only when it must differ from introBackground.',
  'intro.style': 'video plays logo.intro; logoHold shows logo.mark until the app is ready.',
  locales: 'Languages the app ships, as codes separated by commas.',
  defaultLocale: "The language used when the phone's is not in locales.",
  currency: 'The ISO 4217 code prices are shown in, such as EUR.',
  'features.wallet': 'The TransaPay wallet module. Off by default.',
  'support.email': 'The public support address shown in the app, never a personal contact.',
  'support.partnerUrl': 'Where a business applies to resell the brand. Without it, no partner entry.',
  'support.hours.': 'Support hours as users read them, one per language.',
  'legal.companyName': 'The legal entity behind the app.',
  'legal.tradingAs': 'Trading name, when it differs from the company name.',
  'legal.legalForm': 'Company form, such as Ltd or SAS.',
  'legal.country': 'Country of that entity. There is no default, on purpose.',
  'legal.address': 'Registered address, shown on the legal screen.',
  'legal.city': 'City of the registered address.',
  'legal.termsUrl': 'Public https page with the terms. An app cannot open a Drive file.',
  'legal.privacyUrl': 'Public https page with the privacy policy.',
  'legal.accountDeletionUrl': 'Page where a user asks for the account to be deleted. Apple and Play require it.',
  'mobile.applicationId': 'Android package id. Frozen once the app is on Play.',
  'mobile.bundleIdentifier': 'iOS bundle id. Frozen once the app is on the App Store.',
  'mobile.displayName': 'The name under the icon on the phone.',
  'mobile.deepLinkScheme': 'The URL scheme that opens the app, without ://.',
  'mobile.universalLinkHosts': 'Domains whose links open the app, separated by commas.',
  'mobile.apiBaseUrl': 'The PRODUCTION backend, the only one a store build talks to. Pinned in studio.json: Go prod writes it, never this form.',
  'mobile.devApiBaseUrl': 'The DEV backend, for the dev flavor only (ids + .dev, a red banner). Never a production host.',
  'mobile.stripePublishableKey': "The client's own live Stripe key, pk_live_, or the placeholder while payments are off. Never a secret key.",
  'mobile.devStripePublishableKey': "The DEV backend's Stripe pk_test_ key, for the dev flavor only. Never a live or secret key.",
  'mobile.devGoogleIosClientId': 'The iOS OAuth client made for the .dev bundle id. Without it, Google sign-in fails in DEV builds on iOS.',
  'mobile.remoteConfigUrl': 'A configuration the app fetches after its first frame. Without it, the embedded one only.',
  'mobile.minimumSupportedVersion': 'The oldest app version the brand still supports.',
  'mobile.popularDestinations': 'Destinations the Store shelf shows first, as ISO alpha-3 codes.',
  'mobile.registration.fields': 'Sign-up fields, in order. email, firstName, lastName and password must stay.',
  'mobile.cardBackground': "Image behind destination cards, from this brand's assets/.",
  'mobile.googleServerClientId': 'Google web client id. Without it, the Google button is hidden.',
  'mobile.googleIosClientId': 'Google iOS client id. Google sign-in on iOS needs it.',
  'visuals.packImages.': "Header photo for a region's pack cards, or a country's, by ISO alpha-3 code.",
};

function hintFor(path) {
  if (HINTS[path]) return HINTS[path];
  const map = Object.keys(HINTS).find((k) => k.endsWith('.') && path.startsWith(k));
  return map ? HINTS[map] : null;
}

function field(path, key, value) {
  const row = el('div', 'field');
  row.dataset.path = path;
  const id = `f-${path.replace(/[^\w]/g, '_')}`;
  const label = el('label', 'key', key);
  label.htmlFor = id;
  const control = el('div', 'control');
  let input;

  if (typeof value === 'boolean') {
    input = el('input');
    input.type = 'checkbox';
    input.checked = value;
    input.onchange = () => edit(path, input.checked);
  } else if (Array.isArray(value)) {
    input = el('input');
    input.type = 'text';
    input.value = value.join(', ');
    input.title = 'comma-separated';
    input.oninput = () => edit(path, input.value.split(',').map((s) => s.trim()).filter(Boolean));
  } else {
    const text = value === null ? '' : String(value);
    input = el(text.length > 70 ? 'textarea' : 'input');
    if (input.tagName === 'INPUT') input.type = 'text';
    input.value = text;
    input.oninput = () => edit(path, typeof value === 'number' ? Number(input.value) : input.value);
    if (HEX.test(text)) {
      const pick = el('input');
      pick.type = 'color';
      pick.value = text.toLowerCase();
      pick.setAttribute('aria-label', `${key} colour`);
      pick.oninput = () => {
        input.value = pick.value;
        edit(path, pick.value);
      };
      input.addEventListener('input', () => {
        if (HEX.test(input.value)) pick.value = input.value.toLowerCase();
      });
      control.append(pick);
    }
  }
  input.id = id;
  control.prepend(input);

  // The folder name, any store id studio.json says is published, and the
  // production host, which follows the pin (Slice H).
  const published = state.studio[state.slug]?.published ?? {};
  const frozen = path.startsWith('mobile.') && path.slice(7) in published;
  if (path === 'slug' || frozen || path === 'mobile.apiBaseUrl') {
    input.readOnly = true;
    control.append(el('span', 'lock', path === 'slug' ? 'folder name' : frozen ? 'published · frozen' : 'pinned · Go prod writes it'));
  }
  // Where the value came from, while it still is the client intake's.
  const source = intakeTag(path, value);
  if (source) {
    control.append(source);
    input.addEventListener('input', () => source.remove(), { once: true });
  }
  row.append(label, control);
  const hint = hintFor(path);
  if (hint) {
    const line = el('div', 'field-hint', hint);
    line.id = `${id}-hint`;
    input.setAttribute('aria-describedby', line.id);
    row.append(line);
  }
  return row;
}

function renderResult() {
  const r = state.results[state.slug];
  if (!r) return;
  const brand = current();
  const colors = isObject(brand.colors) ? brand.colors : {};

  // Chips.
  const chips = [
    [r.errors.length ? 'err' : 'ok', `${r.errors.length} error${r.errors.length === 1 ? '' : 's'}`],
    [r.warnings.length ? 'warn' : 'ok', `${r.warnings.length} warning${r.warnings.length === 1 ? '' : 's'}`],
    ...(r.frozen.length ? [['err', `${r.frozen.length} frozen id changed`]] : []),
    [r.changes.length ? 'warn' : 'ok', r.changes.length ? `${r.changes.length} file${r.changes.length === 1 ? '' : 's'} to write` : 'files in sync'],
  ];
  for (const [fg, bg, label] of [['ctaText', 'cta', 'CTA'], ['primary', 'surface', 'primary/surface']]) {
    if (HEX.test(colors[fg] ?? '') && HEX.test(colors[bg] ?? '')) {
      const c = contrast(colors[fg], colors[bg]);
      chips.push([c >= 4.5 ? 'ok' : 'warn', `${label} ${c.toFixed(1)}:1${c >= 4.5 ? ' AA' : ' below AA'}`]);
    }
  }
  $('chips').replaceChildren(...chips.map(([level, text]) => el('span', `chip ${level}`, text)));

  // Marks on the form.
  const form = $('form');
  form.querySelectorAll('.msg').forEach((m) => m.remove());
  form.querySelectorAll('.err, .warn').forEach((m) => m.classList.remove('err', 'warn'));
  const problems = [
    ...r.frozen.map((p) => ({ ...p, level: 'err' })),
    ...r.errors.map((p) => ({ ...p, level: 'err' })),
    ...r.warnings.map((p) => ({ ...p, level: 'warn' })),
  ];
  for (const p of problems) {
    const target = targetFor(p.field);
    if (!target) continue;
    if (!target.classList.contains('err')) target.classList.add(p.level);
    if (target.classList.contains('field')) target.append(el('div', 'msg', p.reason));
    for (let d = target.closest('details'); d; d = d.parentElement.closest('details')) {
      if (p.level === 'err') d.open = true;
    }
  }

  // Problem list.
  $('problem-count').textContent = problems.length ? `· ${problems.length}` : '';
  $('problems').replaceChildren(...(problems.length ? problems.map((p) => {
    const li = el('li', p.level);
    const b = el('button');
    b.append(el('span', 'path', p.field), document.createTextNode(p.reason));
    b.onclick = () => {
      const t = targetFor(p.field);
      if (!t) return;
      for (let d = t.closest('details'); d; d = d.parentElement.closest('details')) d.open = true;
      t.scrollIntoView({ block: 'center' });
      t.querySelector('input, textarea')?.focus();
    };
    li.append(b);
    return li;
  }) : [el('li', 'none', 'BrandConfig accepts this brand as it stands.')]));

  // Changes.
  $('change-count').textContent = r.changes.length ? `· ${r.changes.length}` : '';
  $('changes').replaceChildren(...(r.changes.length ? [] : [el('p', 'none', 'Every generated file matches brand.json.')]), ...r.changes.map((c, i) => {
    const d = el('details', 'file');
    d.open = i < 3;
    const s = el('summary', '', c.path);
    if (c.isNew) s.append(el('span', 'new', 'new'));
    const pre = el('pre', 'diff');
    pre.append(...c.diff.trimEnd().split('\n').map((line) => el('span',
      line.startsWith('@@') ? 'hunk' : line[0] === '+' ? 'add' : line[0] === '-' ? 'del' : '', line)));
    d.append(s, pre);
    return d;
  }));

  // Dirty-tree refusal, and Apply.
  const dirty = state.dirty[state.slug];
  $('dirty').hidden = !dirty;
  if (dirty) {
    const ul = el('ul');
    ul.append(...dirty.map((p) => el('li', '', p)));
    const b = el('button', '', `Overwrite these ${dirty.length} file${dirty.length === 1 ? '' : 's'}`);
    b.onclick = () => apply(dirty);
    $('dirty').replaceChildren(el('div', '', 'Git shows changes in these files that are not committed:'), ul, b);
  }
  $('apply').disabled = Boolean(r.errors.length || r.frozen.length || !r.changes.length || dirty);
}

/// The form element a problem's dotted path points at, or its nearest ancestor.
function targetFor(field) {
  const parts = field.split('.');
  while (parts.length) {
    const t = $('form').querySelector(`[data-path="${CSS.escape(parts.join('.'))}"]`);
    if (t) return t;
    parts.pop();
  }
  return null;
}

// ---- shared by Assets and New brand ---------------------------------------

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).split(',')[1]);
    r.onerror = () => reject(r.error);
    r.readAsDataURL(file);
  });
}

/// A drop zone: a dropped file or one chosen by click goes to [onFile].
function dropZone(label, accept, onFile) {
  const zone = el('label', 'drop');
  const input = el('input');
  input.type = 'file';
  input.accept = accept;
  input.hidden = true;
  input.onchange = () => input.files[0] && onFile(input.files[0]);
  zone.append(el('span', '', label), input);
  zone.ondragover = (e) => { e.preventDefault(); zone.classList.add('over'); };
  zone.ondragleave = () => zone.classList.remove('over');
  zone.ondrop = (e) => {
    e.preventDefault();
    zone.classList.remove('over');
    if (e.dataTransfer.files[0]) onFile(e.dataTransfer.files[0]);
  };
  return zone;
}

// The adaptive icon under the three mask families launchers use, with the
// 66 dp safe circle drawn on top. Masks act on the central 72 dp of the
// 108 dp layer: there the mark spans 66% and the safe circle 91.7%.
const SQUIRCLE = (() => {
  const pts = [];
  for (let i = 0; i < 64; i++) {
    const t = (i / 64) * 2 * Math.PI;
    const x = Math.sign(Math.cos(t)) * Math.abs(Math.cos(t)) ** 0.5;
    const y = Math.sign(Math.sin(t)) * Math.abs(Math.sin(t)) ** 0.5;
    pts.push(`${(50 + 50 * x).toFixed(2)}% ${(50 + 50 * y).toFixed(2)}%`);
  }
  return `polygon(${pts.join(',')})`;
})();

/// [viewport]: a data URI of the unmasked icon, or {mark, bg} to compose it
/// from a brand_mark file and the background colour.
function maskTiles(viewport, monochrome) {
  const wrap = el('div', 'masks');
  const shapes = [['circle', 'circle(50%)'], ['squircle', SQUIRCLE], ['square', 'inset(0 round 6%)']];
  for (const [name, clip] of shapes) {
    const tile = el('figure', 'mask');
    const face = el('div', 'face');
    face.style.clipPath = clip;
    if (typeof viewport === 'string') {
      const i = el('img');
      i.src = viewport;
      i.alt = '';
      face.append(i);
    } else {
      face.style.background = viewport.bg;
      const i = el('img', 'mark66');
      i.src = viewport.mark;
      i.alt = '';
      face.append(i);
    }
    const ring = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    ring.setAttribute('viewBox', '0 0 100 100');
    ring.classList.add('safe');
    ring.innerHTML = '<circle cx="50" cy="50" r="45.83" />';
    tile.append(face, ring, el('figcaption', '', name));
    wrap.append(tile);
  }
  if (monochrome) {
    const tile = el('figure', 'mask themed');
    const face = el('div', 'face');
    face.style.clipPath = 'circle(50%)';
    const i = el('img');
    i.src = monochrome;
    i.alt = '';
    face.append(i);
    tile.append(face, el('figcaption', '', 'themed (13+)'));
    wrap.append(tile);
  }
  return wrap;
}

function kb(n) {
  return n > 1048576 ? `${(n / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`;
}

/// A plan (preview of a write) in the side panel: problems, notes, the icon
/// masks, an image grid, text diffs, and the button that writes it.
function renderPlan(plan, { title, applyLabel, onApply, dirty, extra }) {
  const side = $('side-plan');
  const problems = [
    ...plan.errors.map((p) => ({ ...p, level: 'err' })),
    ...plan.warnings.map((p) => ({ ...p, level: 'warn' })),
  ];
  const list = el('ol', 'problems');
  list.append(...(problems.length ? problems.map((p) => {
    const li = el('li', p.level);
    const b = el('button');
    b.type = 'button';
    b.append(el('span', 'path', p.field), document.createTextNode(p.reason));
    li.append(b);
    return li;
  }) : [el('li', 'none', 'No problems.')]));

  const parts = [el('h2', 'label', title), list];
  for (const n of plan.notes.filter((n) => n !== 'strip-available')) parts.push(el('p', 'plan-note', n));
  if (extra) parts.push(extra);
  if (plan.masks) {
    parts.push(el('h2', 'label', 'Launcher icon under each mask · dashed: safe zone'));
    parts.push(maskTiles(plan.masks.viewport, plan.masks.monochrome));
  }
  const images = plan.files.filter((f) => f.preview);
  if (images.length) {
    parts.push(el('h2', 'label', `Images · ${plan.files.length}`));
    const grid = el('div', 'grid');
    grid.append(...images.map((f) => {
      const fig = el('figure', 'thumb');
      const i = el('img');
      i.src = f.preview;
      i.alt = f.path;
      i.onload = () => { meta.textContent = `${i.naturalWidth}×${i.naturalHeight} preview · ${kb(f.bytes)}${f.isNew ? ' · new' : ''}`; };
      const meta = el('span', 'meta', kb(f.bytes));
      fig.append(i, el('figcaption', '', f.path.split('/').slice(-2).join('/')), meta);
      return fig;
    }));
    parts.push(grid);
  }
  const other = plan.files.filter((f) => !f.preview);
  for (const f of other) parts.push(el('p', 'plan-note', `${f.path} · ${kb(f.bytes)}${f.isNew ? ' · new' : ''}`));
  if (plan.changes.length) {
    parts.push(el('h2', 'label', `Text files · ${plan.changes.length}`));
    for (const c of plan.changes) {
      const d = el('details', 'file');
      const s = el('summary', '', c.path);
      if (c.isNew) s.append(el('span', 'new', 'new'));
      const pre = el('pre', 'diff');
      pre.append(...c.diff.trimEnd().split('\n').map((line) => el('span',
        line.startsWith('@@') ? 'hunk' : line[0] === '+' ? 'add' : line[0] === '-' ? 'del' : '', line)));
      d.append(s, pre);
      parts.push(d);
    }
  }
  if (dirty?.length) {
    const box = el('div', 'dirty');
    const ul = el('ul');
    ul.append(...dirty.map((p) => el('li', '', p)));
    const b = el('button', '', `Overwrite these ${dirty.length} file${dirty.length === 1 ? '' : 's'}`);
    b.type = 'button';
    b.onclick = () => onApply(dirty);
    box.append(el('div', '', 'Git shows changes in these files that are not committed:'), ul, b);
    parts.push(box);
  }
  const write = plan.files.length + plan.changes.length;
  const apply = el('button', 'apply', write ? applyLabel : 'Nothing to write');
  apply.type = 'button';
  apply.disabled = Boolean(plan.errors.length || !write || dirty?.length);
  apply.onclick = () => onApply([]);
  parts.push(apply, el('p', 'toast', ''), el('p', 'note', 'Writes these files only. Never commits, never pushes.'));
  side.replaceChildren(...parts);
}

function planStatus(text, isError = false) {
  const t = $('side-plan').querySelector('.toast');
  if (!t) return;
  t.textContent = text;
  t.style.color = isError ? 'var(--err)' : '';
}

// ---- controls --------------------------------------------------------------

document.querySelectorAll('.tab[data-view]').forEach((t) => { t.onclick = () => showView(t.dataset.view); });
$('new-brand').onclick = () => showView('wizard');

$('apply').onclick = () => apply();

$('revert').onclick = () => {
  state.edits[state.slug] = JSON.parse(state.loaded[state.slug]);
  delete state.dirty[state.slug];
  status('');
  select(state.slug);
  preview();
};

$('raw-toggle').onclick = () => {
  state.raw = !state.raw;
  $('raw-toggle').setAttribute('aria-pressed', String(state.raw));
  $('raw').hidden = !state.raw;
  $('form').hidden = state.raw;
  $('raw-error').textContent = '';
  if (state.raw) {
    $('raw-text').value = JSON.stringify(current(), null, 2);
  } else {
    renderForm();
    renderResult();
  }
};

$('raw-text').oninput = () => {
  try {
    const value = JSON.parse($('raw-text').value);
    if (!isObject(value)) throw new Error('brand.json must be a JSON object');
    state.edits[state.slug] = value;
    $('raw-error').textContent = '';
    afterEdit();
  } catch (e) {
    $('raw-error').textContent = e.message;
  }
};

window.addEventListener('beforeunload', (e) => {
  if (state.brands.some((b) => state.edits[b.slug] && edited(b.slug))) e.preventDefault();
});

// ---- theme and tips --------------------------------------------------------

/// This browser's choices. A browser that refuses storage just forgets them.
const prefs = {
  get(key) { try { return localStorage.getItem(key); } catch { return null; } },
  set(key, value) {
    try {
      if (value === null) localStorage.removeItem(key);
      else localStorage.setItem(key, value);
    } catch { /* not remembered */ }
  },
};
const systemLight = matchMedia('(prefers-color-scheme: light)');

/// Auto follows the system, live; Light and Dark are kept in this browser.
/// index.html applies the same choice before the first paint.
function applyTheme() {
  const choice = prefs.get('studio.theme') ?? 'system';
  const light = choice === 'system' ? systemLight.matches : choice === 'light';
  document.documentElement.dataset.theme = light ? 'light' : 'dark';
  document.querySelectorAll('[data-theme-choice]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.themeChoice === choice)));
}

function applyTips() {
  const on = prefs.get('studio.tips') !== 'off';
  document.documentElement.classList.toggle('no-tips', !on);
  $('tips-toggle').setAttribute('aria-pressed', String(on));
}

document.querySelectorAll('[data-theme-choice]').forEach((b) => {
  b.onclick = () => {
    prefs.set('studio.theme', b.dataset.themeChoice === 'system' ? null : b.dataset.themeChoice);
    applyTheme();
  };
});
systemLight.addEventListener('change', applyTheme);
$('tips-toggle').onclick = () => {
  prefs.set('studio.tips', prefs.get('studio.tips') === 'off' ? null : 'off');
  applyTips();
};
applyTheme();
applyTips();

boot().catch((e) => status(`Studio could not load: ${e.message}`, true));
