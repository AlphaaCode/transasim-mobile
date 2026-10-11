// SPC Studio, Integrations tab. Every value that comes from a console outside
// the repo, each with "Get it": the right page for this brand, the steps, the
// values to copy, and a paste box the server checks with the guide's own
// rules. A value only reaches brand.json or studio.json through the previewed
// Apply in the side panel.
'use strict';

const INTEGRATIONS = [
  ['Google Cloud', [
    { field: 'studio:gcpProjectId', label: 'Project ID', hint: 'In Google Cloud console’s project picker: the project ID (or its number, the digits every client ID starts with).' },
    { field: 'studio:googleAccount', label: 'Google account', hint: 'The account that owns the project: Studio opens Google consoles signed in as it.' },
    { guide: 'oauth-consent' },
    { guide: 'google-web-client' },
    { guide: 'google-ios-client' },
    { guide: 'google-android-client' },
  ]],
  ['Signing', [
    { field: 'studio:uploadKeySha1', label: 'Upload key SHA-1', keystore: true, hint: 'Read from this brand’s keystore, or pasted from Play Console (App integrity, upload key certificate).' },
    { guide: 'play-signing-sha1' },
  ]],
  ['Google Play', [
    { guide: 'play-app-id' },
    { field: 'studio:playDeveloperId', label: 'Play developer id', hint: 'Taken from the Play app’s address.' },
  ]],
  ['Apple', [{ guide: 'apple-team-id' }]],
  ['Stripe', [{ guide: 'stripe-publishable-key' }]],
];

// What a missing placeholder is called in this tab.
const NEEDS = { gcpProject: 'Project ID', authuser: 'Google account', devId: 'Play developer id', playAppId: 'Play app',
  uploadSha1: 'Upload key SHA-1', playSigningSha1: 'Play App Signing SHA-1', package: 'applicationId (Brand tab)',
  bundleId: 'bundleIdentifier (Brand tab)', teamId: 'Apple team ID', name: 'name (Brand tab)' };

// A create page's ids the card lets you type on the spot, and where each goes.
const PREREQ_FIELD = { gcpProject: 'studio:gcpProjectId', authuser: 'studio:googleAccount',
  devId: 'studio:playDeveloperId', playAppId: 'studio:playAppId' };

const integ = { guides: {}, missing: [], open: null, lastClip: '', timer: null, seq: 0, result: null };

function studioNow() {
  state.studioEdits[state.slug] ??= JSON.parse(JSON.stringify(state.studio[state.slug] ?? {}));
  return state.studioEdits[state.slug];
}

function getField(field) {
  const [side, path] = [field.slice(0, field.indexOf(':')), field.slice(field.indexOf(':') + 1)];
  return path.split('.').reduce((o, k) => (o == null ? o : o[k]), side === 'brand' ? current() : studioNow());
}

function setField(field, value) {
  const [side, path] = [field.slice(0, field.indexOf(':')), field.slice(field.indexOf(':') + 1)];
  const keys = path.split('.');
  const last = keys.pop();
  let node = side === 'brand' ? current() : studioNow();
  for (const k of keys) node = node[k] ??= {};
  node[last] = value;
}

/// The path the server names a field by: mobile.x, or studio.x.
const pathOf = (field) => field.replace(/^brand:/, '').replace(/^studio:/, 'studio.');

async function fetchGuides() {
  const { data } = await api(`/api/brands/${state.slug}/guides`, { brand: current(), studio: studioNow() });
  integ.guides = Object.fromEntries(data.guides.map((g) => [g.id, g]));
  integ.missing = data.missing;
  // A label is a link to where its value is created; the ids behind it may
  // have just been typed.
  for (const a of document.querySelectorAll('#view-integrations a.key-link')) {
    linkTo(a, integ.guides[a.dataset.guide]?.open);
  }
}

async function renderIntegrations() {
  const slug = state.slug;
  await fetchGuides();
  if (slug !== state.slug || state.view !== 'integrations') return;
  const head = el('div', 'sheet-head');
  const revert = el('button', 'ghost', 'Revert');
  revert.type = 'button';
  revert.onclick = () => {
    state.edits[slug] = JSON.parse(state.loaded[slug]);
    delete state.studioEdits[slug];
    integ.open = null;
    renderIntegrations();
  };
  head.append(el('h1', '', current().name ?? slug), el('div', 'chips'), revert);

  const groups = INTEGRATIONS.map(([title, rows]) => {
    const d = el('details');
    d.open = true;
    const g = el('div', 'group');
    for (const row of rows) g.append(...integrationRow(row));
    d.append(el('summary', '', title), g);
    return d;
  });
  const form = el('div', 'form');
  form.append(...groups);
  $('view-integrations').replaceChildren(head, missingSummary(), form);
  scheduleIntegrations();
}

function integrationRow(spec) {
  const g = spec.guide ? integ.guides[spec.guide] : null;
  const field = g ? g.field : spec.field;
  const path = field ? pathOf(field) : `studio.checklist.${g.checklistItem}`;
  const row = el('div', 'field integ');
  row.dataset.path = path;
  const text = spec.label ?? g.title;
  // A guided label opens where the value is created, like Get it; a plain
  // field keeps an ordinary label.
  const label = g ? el('a', 'key key-link', text) : el('label', 'key', text);
  if (g) {
    label.dataset.guide = g.id;
    label.target = '_blank';
    label.rel = 'noopener';
    label.title = 'Opens where this value is created, with its guide';
    linkTo(label, g.open);
    label.onclick = (e) => {
      if (!label.getAttribute('href')) e.preventDefault();
      showGuide(g.id);
    };
    // Until it has a page, the label is a button that opens the guide, so
    // it answers Space as well as Enter.
    label.onkeydown = (e) => {
      if (label.getAttribute('href') || (e.key !== 'Enter' && e.key !== ' ')) return;
      e.preventDefault();
      showGuide(g.id);
    };
  }
  const control = el('div', 'control');

  if (field) {
    const input = el('input');
    input.type = 'text';
    input.id = `i-${path.replace(/\W/g, '_')}`;
    if (g) input.setAttribute('aria-label', text); else label.htmlFor = input.id;
    input.value = getField(field) ?? '';
    input.oninput = () => { setField(field, input.value.trim()); scheduleIntegrations(); };
    control.append(input);
  } else {
    const rec = g.confirmed;
    control.append(el('span', 'confirm-state', rec ? `done ${rec.doneAt}${rec.note ? ` · ${rec.note}` : ''}` : 'not confirmed yet'));
  }
  if (g) {
    const get = el('button', 'ghost get', 'Get it');
    get.type = 'button';
    get.onclick = () => getIt(g.id);
    control.append(get);
  }
  if (spec.keystore) {
    const read = el('button', 'ghost', 'Read from keystore');
    read.type = 'button';
    read.onclick = async () => {
      read.disabled = true;
      const { data } = await api(`/api/brands/${state.slug}/upload-sha1`, {});
      read.disabled = false;
      if (data.sha1) {
        setField(field, data.sha1);
        row.querySelector('input').value = data.sha1;
        scheduleIntegrations();
      } else {
        showRowMessage(row, data.error, 'warn');
      }
    };
    control.append(read);
  }
  row.append(label, control);
  if (spec.hint) row.append(el('div', 'msg hint', spec.hint));
  const card = el('div', 'guide-card');
  card.hidden = true;
  if (g) card.dataset.guide = g.id;
  return [row, card];
}

function showRowMessage(row, text, level) {
  row.querySelectorAll('.msg:not(.hint)').forEach((m) => m.remove());
  row.classList.remove('err', 'warn');
  if (!text) return;
  row.classList.add(level);
  row.append(el('div', 'msg', text));
}

/// A label is a link once its page is known, a button (opening the guide)
/// until then: an anchor without href has no role for assistive tech.
function linkTo(a, url) {
  if (url) {
    a.href = url;
    a.removeAttribute('role');
    a.removeAttribute('tabindex');
  } else {
    a.removeAttribute('href');
    a.setAttribute('role', 'button');
    a.tabIndex = 0;
  }
}

/// "Get it": the page where the value is created, in a new tab, and the guide
/// card beside the field.
async function getIt(id) {
  await fetchGuides(); // the URL follows ids typed a moment ago
  const g = integ.guides[id];
  if (g.open) window.open(g.open, '_blank', 'noopener');
  showGuide(id);
}

/// The guide card alone, scrolled into view: what a label link and the
/// Missing data list open (a label link also opens the console page itself).
async function showGuide(id) {
  await fetchGuides();
  integ.open = id;
  integ.lastClip = '';
  document.querySelectorAll('.guide-card').forEach((c) => { c.hidden = c.dataset.guide !== id; });
  renderCard(integ.guides[id]);
  const card = document.querySelector(`.guide-card[data-guide="${id}"]`);
  card.scrollIntoView({ block: 'nearest' });
  (card.querySelector('.prereq input') ?? card.querySelector('h3')).focus();
}

/// What the brand still lacks, at the top of the tab, each item one click
/// from its guide (or its field).
function missingSummary() {
  const box = el('section', 'missing');
  box.setAttribute('aria-labelledby', 'missing-title');
  const title = el('h2', 'label', integ.missing.length ? `Missing data · ${integ.missing.length}` : 'Missing data · none');
  title.id = 'missing-title';
  box.append(title);
  if (!integ.missing.length) return box;
  const list = el('ul');
  for (const m of integ.missing) {
    const b = el('button', 'missing-item');
    b.type = 'button';
    b.append(el('span', 'k', m.label), el('span', 'v', m.reason));
    b.onclick = () => {
      if (m.guide) return showGuide(m.guide);
      const input = document.getElementById(`i-${m.id.replace(/\W/g, '_')}`);
      input?.scrollIntoView({ block: 'center' });
      input?.focus();
    };
    const li = el('li');
    li.append(b);
    list.append(li);
  }
  box.append(list);
  return box;
}

function renderCard(g) {
  const card = document.querySelector(`.guide-card[data-guide="${g.id}"]`);
  const h = el('h3', '', g.title);
  h.tabIndex = -1;
  const parts = [h];
  if (g.open) {
    const a = el('a', '', `Open ${g.open.replace(/^https:\/\//, '').slice(0, 90)}`);
    a.href = g.open;
    a.target = '_blank';
    a.rel = 'noopener';
    parts.push(a);
  }
  // The ids this page needs, typed right here instead of a dead end.
  const prereqs = g.prerequisites.filter((k) => g.missing.includes(k));
  if (prereqs.length) {
    const box = el('div', 'prereq');
    box.append(el('p', 'needs', 'To open the page where this is created, Studio needs:'));
    for (const k of prereqs) {
      const id = `p-${g.id}-${k}`;
      const lab = el('label', '', NEEDS[k] ?? k);
      lab.htmlFor = id;
      const input = el('input');
      input.type = 'text';
      input.id = id;
      input.value = getField(PREREQ_FIELD[k]) ?? '';
      input.oninput = () => {
        setField(PREREQ_FIELD[k], input.value.trim());
        const rowInput = document.getElementById(`i-${pathOf(PREREQ_FIELD[k]).replace(/\W/g, '_')}`);
        if (rowInput) rowInput.value = input.value.trim();
        scheduleIntegrations();
      };
      input.onchange = () => showGuide(g.id); // re-resolve once the value is in
      box.append(lab, input);
    }
    parts.push(box);
  }
  if (g.prerequisites.includes('gcpProject') && /^\d+$/.test(getField('studio:gcpProjectId') ?? '')) {
    // Verified 2026-10-11: the console accepts the number and rewrites the
    // address to the project ID (Sabily's 83118739145 became "sabily").
    const box = el('div', 'prereq');
    box.append(el('p', 'needs', 'That is the project number. The console accepts it and rewrites the address to the project ID. To store the ID instead, paste it, or the console address, here:'));
    const lab = el('label', '', 'Project ID');
    lab.htmlFor = `r-${g.id}`;
    const input = el('input');
    input.type = 'text';
    input.id = `r-${g.id}`;
    input.placeholder = 'e.g. sabily, or https://console.cloud.google.com/…?project=sabily';
    input.onchange = () => {
      const text = input.value.trim();
      let id = text;
      try { id = new URL(text).searchParams.get('project') ?? ''; } catch { /* not a URL: the ID itself */ }
      // The server's rule decides; a value it refuses shows in the preview, as any other.
      if (!id) return;
      setField('studio:gcpProjectId', id);
      const rowInput = document.getElementById('i-studio_gcpProjectId');
      if (rowInput) rowInput.value = id;
      scheduleIntegrations();
      showGuide(g.id);
    };
    box.append(lab, input);
    parts.push(box);
  }
  const others = g.missing.filter((k) => !prereqs.includes(k));
  if (others.length) parts.push(el('p', 'needs', `Also needed: ${others.map((k) => NEEDS[k] ?? k).join(', ')}.`));
  if (g.open || g.alternatives.length) {
    const alts = el('div', 'alts');
    alts.append(el('span', '', g.alternatives.length ? 'Not the create page? Try:' : 'Landed on the right page?'));
    const worked = (index, url) => {
      const b = el('button', 'ghost', 'This one worked');
      b.type = 'button';
      b.setAttribute('aria-label', `This one worked: ${url.replace(/^https:\/\//, '').split('?')[0]}`);
      b.onclick = () => {
        setField(`studio:guideLinks.${g.id}`, index);
        scheduleIntegrations();
        showGuide(g.id);
      };
      return b;
    };
    if (g.openIndex >= 0) alts.append(worked(g.openIndex, g.open));
    for (const alt of g.alternatives) {
      const a = el('a', '', alt.url.replace(/^https:\/\//, '').slice(0, 70));
      a.href = alt.url;
      a.target = '_blank';
      a.rel = 'noopener';
      alts.append(a);
      if (alt.index >= 0) alts.append(worked(alt.index, alt.url));
    }
    parts.push(alts);
  }
  const steps = el('ol', 'steps');
  steps.append(...g.steps.map((s) => el('li', '', s)));
  parts.push(steps);
  if (g.copyValues.length) {
    const copies = el('div', 'copies');
    for (const c of g.copyValues) {
      const b = el('button', 'copy');
      b.type = 'button';
      b.append(el('span', 'k', c.label), el('span', 'v', c.value));
      b.onclick = async () => {
        await navigator.clipboard.writeText(c.value);
        b.classList.add('done');
        setTimeout(() => b.classList.remove('done'), 1200);
      };
      copies.append(b);
    }
    parts.push(copies);
  }
  if (g.kind === 'paste') parts.push(pasteBox(g));
  else parts.push(confirmBox(g));
  card.replaceChildren(...parts);
}

function pasteBox(g) {
  const box = el('div', 'paste');
  const input = el('input');
  input.type = 'text';
  input.placeholder = 'Paste the value here';
  input.setAttribute('aria-label', `${g.title}: paste`);
  const verdict = el('div', 'verdict');
  const offer = el('div', 'offer');
  const use = el('button', 'apply', 'Use this value');
  use.type = 'button';
  use.disabled = true;
  let last = null;
  const run = async () => {
    const value = input.value;
    if (!value.trim()) { verdict.replaceChildren(); use.disabled = true; return; }
    last = await checkValue(g, value);
    renderVerdict(verdict, last);
    use.disabled = Boolean(last.errors.length);
  };
  input.oninput = () => { clearTimeout(integ.timer); integ.timer = setTimeout(run, 200); };
  use.onclick = () => useValue(g, last);
  box.append(input, verdict, use, offer);
  return box;
}

async function checkValue(g, value) {
  const { data } = await api(`/api/brands/${state.slug}/guides/${g.id}/check`, { value, brand: current(), studio: studioNow() });
  return data;
}

function renderVerdict(target, v) {
  target.replaceChildren(...(v.errors.length
    ? v.errors.map((e) => el('p', 'bad', e))
    : [el('p', 'good', `Valid: ${v.value}`), ...v.derived.map((d) => el('p', 'derived', `${d.label}: ${d.value}`))]));
}

/// The value goes into the pending edit only; the side panel's Apply writes it.
function useValue(g, v) {
  if (!v || v.errors.length) return;
  setField(g.field, v.value);
  for (const d of v.derived) if (d.field && d.field !== g.field) setField(d.field, d.value);
  integ.open = null;
  renderIntegrations();
}

function confirmBox(g) {
  const box = el('div', 'paste');
  if (g.missing.length) {
    box.append(el('p', 'needs', 'It can be ticked once those are set.'));
    return box;
  }
  const note = el('input');
  note.type = 'text';
  note.placeholder = 'What you saw (optional)';
  note.setAttribute('aria-label', `${g.title}: note`);
  const done = el('button', 'apply', 'Record as done');
  done.type = 'button';
  done.onclick = () => {
    const checklist = studioNow().checklist ??= {};
    checklist[g.checklistItem] = {
      doneAt: new Date().toISOString().slice(0, 10),
      ...(note.value.trim() ? { note: note.value.trim() } : {}),
      for: g.requiresNow,
    };
    integ.open = null;
    renderIntegrations();
  };
  box.append(note, done);
  return box;
}

// Back from the console with a value copied: if it passes the open guide's
// check, offer it in one click. Reading the clipboard needs the browser's
// permission; without it, one click on "Read clipboard" does the same.
async function offerClipboard() {
  const g = integ.open && integ.guides[integ.open];
  if (!g || g.kind !== 'paste' || state.view !== 'integrations') return;
  const card = document.querySelector(`.guide-card[data-guide="${g.id}"]`);
  const offer = card?.querySelector('.offer');
  if (!offer) return;
  let text;
  try {
    text = await navigator.clipboard.readText();
  } catch {
    const b = el('button', 'ghost', 'Read clipboard');
    b.type = 'button';
    b.onclick = () => { integ.lastClip = ''; offerClipboard(); };
    offer.replaceChildren(b);
    return;
  }
  text = (text ?? '').trim();
  // Only a short single line is ever considered, and nothing is shown unless it passes.
  if (!text || text === integ.lastClip || text.length > 300 || text.includes('\n')) return;
  integ.lastClip = text;
  const v = await checkValue(g, text);
  if (v.errors.length) { offer.replaceChildren(); return; }
  const b = el('button', 'apply', `Use pasted value: ${v.value.length > 40 ? `${v.value.slice(0, 40)}…` : v.value}`);
  b.type = 'button';
  b.onclick = () => useValue(g, v);
  offer.replaceChildren(b);
}
window.addEventListener('focus', offerClipboard);
document.addEventListener('visibilitychange', () => { if (!document.hidden) offerClipboard(); });

function scheduleIntegrations() {
  clearTimeout(integ.timer);
  integ.timer = setTimeout(previewIntegrations, 300);
}

async function previewIntegrations(acceptDirty) {
  if (state.view !== 'integrations') return;
  const slug = state.slug;
  const seq = ++integ.seq;
  const { data } = await api(`/api/brands/${slug}/integrations/preview`, { brand: current(), studio: studioNow() });
  if (seq !== integ.seq || slug !== state.slug) return;
  integ.result = data;
  markIntegrations(data);
  renderRail();
  renderPlan(data, {
    title: `Integrations · ${current().name}`,
    applyLabel: 'Apply',
    dirty: Array.isArray(acceptDirty) ? acceptDirty : undefined,
    onApply: async (accepted) => {
      const r = await api(`/api/brands/${slug}/integrations/apply`, { brand: current(), studio: studioNow(), acceptDirty: accepted });
      if (r.status === 409) return previewIntegrations(r.data.dirty);
      if (r.status !== 200) return planStatus(r.data.refused || r.data.error, true);
      await load(slug);
      delete state.studioEdits[slug];
      await renderIntegrations();
      planStatus(`Wrote ${r.data.written.length} file${r.data.written.length === 1 ? '' : 's'}. Review and commit when ready.`);
    },
  });
}

/// Each row's state: set, missing or invalid, and the reason next to it.
function markIntegrations(plan) {
  for (const row of document.querySelectorAll('#view-integrations .field.integ')) {
    const path = row.dataset.path;
    const err = plan.errors.find((e) => e.field === path);
    const warn = plan.warnings.find((e) => e.field === path);
    showRowMessage(row, err?.reason ?? warn?.reason, err ? 'err' : 'warn');
    const input = row.querySelector('input');
    const set = input ? input.value.trim() !== '' : !row.querySelector('.confirm-state')?.textContent.startsWith('not');
    let chip = row.querySelector('.chip');
    if (!chip) { chip = el('span', 'chip'); row.querySelector('.control').append(chip); }
    chip.className = `chip ${err ? 'err' : !set || warn ? 'warn' : 'ok'}`;
    chip.textContent = err ? 'invalid' : !set ? 'missing' : warn ? 'check' : 'set';
  }
}
