// SPC Studio, the client intake (Slice I): the spc-intake-<slug>.json the
// onboarding portal writes, dropped with its folder. The server reads it
// strictly; this page shows what it says with textContent only, fetches
// nothing it names, and applies it through the usual previewed Apply.
'use strict';

const INTAKE_MAX = 30 * 1024 * 1024;
const intakeState = { read: null, offer: null, take: new Set(), slug: null, status: {} };

/// The files of a drop, captured while the event lasts: a dropped folder is
/// walked (Chrome's entries API), anything else is taken as dropped.
function captureDrop(dt) {
  const files = [...(dt?.files ?? [])];
  const entries = [...(dt?.items ?? [])].filter((i) => i.kind === 'file').map((i) => i.webkitGetAsEntry?.()).filter(Boolean);
  if (!entries.some((e) => e.isDirectory)) return Promise.resolve(files);
  const out = [];
  const walk = async (entry, depth) => {
    if (entry.isFile) {
      out.push(await new Promise((ok, no) => entry.file(ok, no)));
    } else if (entry.isDirectory && depth < 4) {
      const reader = entry.createReader();
      for (;;) {
        const batch = await new Promise((ok, no) => reader.readEntries(ok, no));
        if (!batch.length) break;
        for (const e of batch) await walk(e, depth + 1);
      }
    }
  };
  return (async () => { for (const e of entries) await walk(e, 0); return out; })();
}

/// The intake's status for [key] ("wizard" or "brand:<slug>"), kept across re-renders.
function intakeSay(key, text, isError = false) {
  intakeState.status[key] = { text, isError };
  for (const s of document.querySelectorAll(`.intake-said[data-intake-key="${CSS.escape(key)}"]`)) paintSaid(s, key);
}

function paintSaid(s, key) {
  const st = intakeState.status[key];
  s.textContent = st?.text ?? '';
  s.classList.toggle('err', Boolean(st?.isError));
}

function intakeStatusLine(key) {
  const s = el('p', 'intake-said');
  s.dataset.intakeKey = key;
  s.setAttribute('role', 'status');
  paintSaid(s, key);
  return s;
}

/// Reads [files] (an array, or the promise captureDrop gives) and says what happened, always.
async function intakeSend(key, slug, files, onRead) {
  try {
    const list = await files;
    if (!list.length) return intakeSay(key, 'Nothing to read: drop the intake folder, its zip, or the JSON.', true);
    const total = list.reduce((n, f) => n + f.size, 0);
    if (total > INTAKE_MAX) return intakeSay(key, `${list.length} files, more than 30 MB: drop the intake folder only.`, true);
    intakeSay(key, `Reading ${list.length} file${list.length === 1 ? '' : 's'}…`);
    const payload = await Promise.all(list.map(async (f) => ({ name: f.name, data: await fileToBase64(f) })));
    const { status: code, data } = await api('/api/intake/read', { files: payload, slug });
    if (code !== 200 || data.refusal || data.error) return intakeSay(key, `Refused: ${data.refusal ?? data.error}`, true);
    intakeSay(key, `Read: ${data.rows.length} rows from client intake ${data.submissionId} (${list.length} file${list.length === 1 ? '' : 's'}).`);
    onRead(data);
  } catch (e) {
    intakeSay(key, `Could not read the dropped files: ${e.message ?? e}`, true);
  }
}

/// Makes [box] an intake drop target, the whole of it. Drops reach it through
/// the page-level handler below, wherever inside it they land.
function intakePanel(box, key, slug, onRead) {
  box.classList.add('intake-panel');
  box.dataset.intakeKey = key;
  box.intakeFiles = (files) => intakeSend(key, slug, files, onRead);
  return box;
}

/// The empty panel's content: what to drop, and a button for the file picker.
function intakeZone(key) {
  const input = el('input');
  Object.assign(input, { type: 'file', multiple: true, hidden: true, accept: '.json,.zip,image/png,image/jpeg' });
  input.onchange = () => input.closest('.intake-panel')?.intakeFiles([...input.files]);
  const pick = el('button', 'ghost', 'Choose files…');
  pick.type = 'button';
  pick.onclick = () => input.click();
  const zone = el('div', 'intake-zone');
  zone.append(el('p', 'intake-hint', 'Drop the client intake anywhere in this box: its Drive folder, the zip, or spc-intake-….json with the logo.'),
    pick, input, intakeStatusLine(key));
  return zone;
}

// The page never opens a dropped file: a drop outside a zone is refused, and a
// drop anywhere inside an intake panel goes to that panel.
document.addEventListener('dragover', (e) => {
  e.preventDefault();
  const panel = e.target.closest?.('.intake-panel');
  for (const p of document.querySelectorAll('.intake-panel.over')) if (p !== panel) p.classList.remove('over');
  if (panel) {
    panel.classList.add('over');
    e.dataTransfer.dropEffect = 'copy';
  } else if (!e.target.closest?.('.drop')) {
    e.dataTransfer.dropEffect = 'none';
  }
});
document.addEventListener('dragleave', (e) => {
  if (!e.relatedTarget) for (const p of document.querySelectorAll('.intake-panel.over')) p.classList.remove('over');
});
document.addEventListener('drop', (e) => {
  e.preventDefault();
  for (const p of document.querySelectorAll('.intake-panel.over')) p.classList.remove('over');
  const panel = e.target.closest?.('.intake-panel');
  if (panel?.intakeFiles) panel.intakeFiles(captureDrop(e.dataTransfer));
});

const shown = (v) => (v === null || v === undefined ? '' : Array.isArray(v) ? v.join(', ') : String(v));

/// What the intake says beyond the values applied: asks, work, information, drops.
function intakeLists(read) {
  const wrap = el('div', 'intake-lists');
  for (const [kind, title] of [['ask', 'Ask the client'], ['todo', 'To do'], ['dropped', 'Dropped (malformed)'], ['info', 'Information']]) {
    const rows = read.rows.filter((r) => r.kind === kind);
    if (!rows.length) continue;
    const ul = el('ul', `intake-${kind}`);
    for (const r of rows) {
      const li = el('li');
      li.append(el('span', 'path', r.path), document.createTextNode(` ${[shown(r.value), r.note].filter(Boolean).join(' · ')}`));
      ul.append(li);
    }
    wrap.append(el('h3', 'label', `${title} · ${rows.length}`), ul);
  }
  return wrap;
}

function intakeHead(read) {
  return el('p', 'plan-note', `Client intake ${read.submissionId}, submitted ${read.submittedAt}. `
    + 'Every value below is the client\'s, except those marked suggested. Nothing is written until you apply.');
}

// ---- the Brand tab: an offer to tick, then a previewed Apply ----------------

function renderBrandIntake() {
  const box = $('intake-brand');
  if (!box) return;
  const slug = state.slug;
  if (intakeState.slug !== slug) Object.assign(intakeState, { read: null, offer: null, take: new Set(), slug });
  const key = `brand:${slug}`;
  // The whole box takes a drop, an intake already shown included: a new one replaces it.
  intakePanel(box, key, slug, (data) => {
    intakeState.read = data;
    intakeState.offer = data.offer ?? [];
    intakeState.take = new Set(intakeState.offer.filter((o) => o.take).map((o) => o.path));
    renderBrandIntake();
  });
  if (!intakeState.read) {
    box.replaceChildren(intakeZone(key));
    return;
  }
  const read = intakeState.read;
  const table = el('table', 'intake-offer');
  const head = el('tr');
  for (const h of ['Apply', 'Field', 'Now', 'Client intake', 'From']) head.append(el('th', '', h));
  table.append(head);
  for (const o of intakeState.offer) {
    const tr = el('tr');
    const box = el('input');
    box.type = 'checkbox';
    box.id = `take-${o.path.replace(/[^\w]/g, '_')}`;
    box.checked = intakeState.take.has(o.path);
    box.onchange = () => { box.checked ? intakeState.take.add(o.path) : intakeState.take.delete(o.path); };
    const label = el('label', 'path', o.path);
    label.htmlFor = box.id;
    const td = el('td');
    td.append(box);
    const lab = el('td');
    lab.append(label);
    tr.append(td, lab, el('td', 'now', shown(o.current) || '(blank)'),
      el('td', '', `${shown(o.value)}${o.suggestion ? ' (suggested)' : ''}`), el('td', 'from', [o.from, o.note].filter(Boolean).join(' · ')));
    table.append(tr);
  }
  const go = el('button', 'apply', 'Preview the ticked changes');
  go.type = 'button';
  go.onclick = () => previewBrandIntake();
  const close = el('button', 'ghost', 'Close the intake');
  close.type = 'button';
  close.onclick = () => {
    Object.assign(intakeState, { read: null, offer: null, take: new Set() });
    delete intakeState.status[key];
    $('side-plan').hidden = true;
    $('side-brand').hidden = false;
    renderBrandIntake();
  };
  const actions = el('div', 'intake-actions');
  actions.append(go, close);
  box.replaceChildren(el('h2', 'label', 'Client intake'), intakeStatusLine(key), intakeHead(read), table,
    el('p', 'note', 'Ticked by default only where the brand is blank. The logo replaces the mark file; the icons stay until Regenerate assets.'),
    actions, intakeLists(read));
}

async function previewBrandIntake(acceptDirty) {
  const slug = state.slug;
  const body = { text: intakeState.read.text, mark: intakeState.read.mark, take: [...intakeState.take] };
  const { status: code, data } = await api(`/api/brands/${slug}/intake/preview`, body);
  $('side-brand').hidden = true;
  $('side-plan').hidden = false;
  if (code !== 200) { renderPlan({ errors: [{ field: 'intake', reason: data.error }], warnings: [], notes: [], files: [], changes: [] }, { title: 'Client intake', applyLabel: 'Apply', onApply: () => {} }); return; }
  renderPlan(data, {
    title: `Client intake · ${slug}`,
    applyLabel: `Apply ${intakeState.take.size} value${intakeState.take.size === 1 ? '' : 's'}`,
    dirty: Array.isArray(acceptDirty) ? acceptDirty : undefined,
    onApply: (accept) => applyBrandIntake(accept),
  });
}

async function applyBrandIntake(acceptDirty) {
  const slug = state.slug;
  const body = { text: intakeState.read.text, mark: intakeState.read.mark, take: [...intakeState.take], acceptDirty };
  const { status: code, data } = await api(`/api/brands/${slug}/intake/apply`, body);
  if (code === 409) return previewBrandIntake(data.dirty);
  if (code !== 200) return planStatus(data.refused || data.error, true);
  Object.assign(intakeState, { read: null, offer: null, take: new Set() });
  await load(slug);
  $('side-plan').hidden = true;
  $('side-brand').hidden = false;
  select(slug);
  status(`Client intake applied: ${data.written.length} files. Review, then commit.`);
}

/// The Brand tab's tag on a field whose value is still the one the intake gave.
function intakeTag(path, value) {
  const intake = state.studio[state.slug]?.intake;
  if (!intake?.applied || !(path in intake.applied)) return null;
  if (JSON.stringify(intake.applied[path]) !== JSON.stringify(value)) return null;
  const tag = el('span', 'src', `client intake ${String(intake.submissionId).slice(0, 8)}`);
  tag.title = `From client intake ${intake.submissionId}, submitted ${intake.submittedAt}`;
  return tag;
}

// ---- New brand: the intake fills the form ------------------------------------

/// Fills the New brand form from an intake, keeping its text for the Apply.
function wizardFromIntake(read) {
  const f = wizard.form;
  for (const [k, v] of Object.entries(read.form ?? {})) {
    if (k === 'colors') Object.assign(f.colors, v);
    else f[k] = v;
  }
  wizard.idEdited = Boolean(read.form?.applicationId);
  wizard.intake = read;
  if (read.mark) {
    wizard.logo = read.mark;
    wizard.logoName = read.rows.find((r) => r.path === 'logo.mark' && r.kind === 'client')?.value ?? 'logo from the intake';
  }
  renderWizard();
}

/// The New brand panel: the zone, or what the dropped intake said.
function wizardIntakePanel() {
  const box = intakePanel(el('div', 'intake-wizard'), 'wizard', null, wizardFromIntake);
  if (!wizard.intake) {
    box.append(intakeZone('wizard'));
    return box;
  }
  const close = el('button', 'ghost', 'Forget the intake');
  close.type = 'button';
  close.onclick = () => { wizard.intake = null; delete intakeState.status.wizard; renderWizard(); };
  box.append(el('h2', 'label', 'Client intake'), intakeStatusLine('wizard'), intakeHead(wizard.intake), close, intakeLists(wizard.intake));
  return box;
}

/// The source of a New brand field: the intake's, while the value still is.
function wizardTag(path, value) {
  const r = wizard.intake?.rows.find((x) => x.path === path && (x.kind === 'client' || x.kind === 'suggested'));
  if (!r || JSON.stringify(r.value) !== JSON.stringify(value)) return null;
  return el('span', 'src', r.kind === 'suggested' ? 'suggested by Studio' : `client intake ${wizard.intake.submissionId.slice(0, 8)}`);
}

// ---- the Backend tab: what the client provided, shown and never gating -------

/// [path, value] for every leaf of [node].
const leaves = (node, path = '') => (isObject(node)
  ? Object.entries(node).flatMap(([k, v]) => leaves(v, path ? `${path}.${k}` : k))
  : [[path, node]]);

function clientIntakeSection() {
  const intake = state.studio[state.slug]?.intake;
  if (!intake) return null;
  const sec = el('section', 'be-section intake-backend');
  sec.append(el('h2', 'label', 'Client intake · shown only, never a gate'),
    el('p', 'plan-note', `From client intake ${intake.submissionId}, submitted ${intake.submittedAt}. `
      + 'Nothing here passes or blocks an item: confirm each value where it is used.'));
  const domains = intake.prodPending?.domains ?? [];
  if (domains.length) {
    sec.append(el('h3', 'label', 'PROD domains, pending'),
      el('p', 'note', `${domains.join(', ')}. They become PROD's only when entered in PROD's fields and applied.`));
  }
  const provided = leaves(intake.clientProvided ?? {}).filter(([, v]) => v !== undefined);
  if (provided.length) {
    const dl = el('dl', 'intake-provided');
    for (const [k, v] of provided) dl.append(el('dt', '', k), el('dd', '', `${shown(v)} · client-provided`));
    sec.append(el('h3', 'label', 'Client-provided'), dl);
  }
  if (intake.stripped?.length) {
    sec.append(el('h3', 'label', 'Client sent credentials separately'),
      el('p', 'note', `${intake.stripped.join(', ')}: never in the intake, never in Studio. Ask for them through the agreed channel.`));
  }
  return sec;
}
