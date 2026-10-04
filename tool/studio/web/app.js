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
  state.results[slug] = data;
}

async function boot() {
  state.brands = (await api('/api/brands')).data;
  await Promise.all(state.brands.map((b) => load(b.slug)));
  const wanted = location.hash.slice(1);
  select(state.brands.some((b) => b.slug === wanted) ? wanted : state.brands[0].slug);
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
  renderResult();
  showView(state.view === 'wizard' ? 'brand' : state.view);
}

/// Brand, Assets or the New brand page; the side panel follows.
function showView(view) {
  state.view = view;
  for (const v of ['brand', 'assets', 'wizard']) $(`view-${v}`).hidden = v !== view;
  document.querySelectorAll('.tab[data-view]').forEach((t) => t.classList.toggle('is-active', t.dataset.view === view));
  $('side-brand').hidden = view !== 'brand';
  $('side-plan').hidden = view === 'brand';
  $('proof').hidden = view === 'wizard';
  $('new-brand').classList.toggle('is-active', view === 'wizard');
  if (view === 'assets') renderAssets();
  if (view === 'wizard') renderWizard();
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

  // The folder name, and any store id studio.json says is published.
  const published = state.studio[state.slug]?.published ?? {};
  const frozen = path.startsWith('mobile.') && path.slice(7) in published;
  if (path === 'slug' || frozen) {
    input.readOnly = true;
    control.append(el('span', 'lock', path === 'slug' ? 'folder name' : 'published · frozen'));
  }
  row.append(label, control);
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

boot().catch((e) => status(`Studio could not load: ${e.message}`, true));
