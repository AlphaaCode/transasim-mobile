// SPC Studio, Store tab (slice S of docs/PLATFORM-PLAN.md): the Play listing's
// graphics, made from the brand's own files, and phone screenshots captured
// from the emulator at 1080×1920. Everything lands in dist/<slug>/store, which
// git ignores; uploading stays a human's step in Play Console.
'use strict';

let storeData = null;

async function renderStore() {
  const slug = state.slug;
  $('view-store').replaceChildren(el('p', 'none', 'Making the graphics…'));
  $('side-plan').replaceChildren(el('p', 'none', 'Reading the store kit…'));
  const { data } = await api(`/api/brands/${slug}/store`);
  if (slug !== state.slug || state.view !== 'store') return;
  storeData = data;
  drawStore();
}

function drawStore(said = '', isError = false) {
  const d = storeData;
  const head = el('div', 'sheet-head');
  head.append(el('h1', '', current().name ?? state.slug));
  const status = el('p', 'toast');
  status.id = 'store-status';
  status.setAttribute('role', 'status');

  // The graphics, as they would be written now.
  const graphics = el('section', 'asset-group');
  graphics.append(el('h2', 'label', 'Graphics'));
  const grid = el('div', 'slots store-graphics');
  grid.append(...d.graphics.map((g) => {
    const card = el('div', 'slot');
    card.append(el('h3', '', g.label));
    if (g.error) {
      card.append(el('p', 'hint bad', g.error));
    } else {
      const i = el('img', 'store-img');
      i.src = g.preview;
      i.alt = `${g.label}, as Studio would write it`;
      card.append(i, el('p', `meta${g.current ? ' good' : ''}`,
        g.current ? `Written: ${d.dir}/${g.file}` : g.written ? 'Out of date in dist: write it again' : 'Not written yet'));
    }
    return card;
  }));
  const write = el('button', 'apply', 'Write both graphics');
  write.type = 'button';
  write.disabled = d.graphics.some((g) => g.error);
  write.onclick = () => storePost('graphics');
  graphics.append(grid, write);

  // Phone screenshots: capture mode, the button, and each file checked.
  const shots = el('section', 'asset-group');
  shots.append(
    el('h2', 'label', `Phone screenshots · ${d.shots.length}`),
    el('p', 'plan-note', 'Build for the store first: the app as brand.json says, on its real backend '
      + '(Build for test talks to DEV). Browse, but do not buy: a purchase there is real. '
      + `Then start capture mode: the emulator switches to ${d.shotSize} with a clean status bar. `
      + 'Open each screen in the app, press Capture, and end capture mode when done. '
      + 'Play needs 2 to 8; 4 at 1080 px make the listing eligible for promotion.'),
  );
  const tools = el('div', 'store-tools');
  const button = (label, cls, onclick) => {
    const b = el('button', cls, label);
    b.type = 'button';
    b.onclick = onclick;
    return b;
  };
  tools.append(
    button('Build for the store', 'ghost', () => storeJob('build-store')),
    button('Start capture mode', 'ghost', () => storeJob('store-capture-on')),
    button('Capture screen', 'apply', () => storePost('shot')),
    button('End capture mode', 'ghost', () => storeJob('store-capture-off')),
  );
  const list = el('div', 'slots store-shots');
  list.append(...(d.shots.length ? d.shots.map((s) => {
    const card = el('div', 'slot');
    if (s.preview) {
      const i = el('img', 'store-shot');
      i.src = s.preview;
      i.alt = s.file;
      card.append(i);
    }
    card.append(el('p', 'meta', s.width ? `${s.file} · ${s.width}×${s.height}` : s.file));
    card.append(...(s.problems.length
      ? s.problems.map((p) => el('p', 'hint bad', p))
      : [el('p', 'hint good', s.promotable ? 'Ready, at promotion size' : 'Ready')]));
    card.append(button('Remove', 'ghost', () => storePost('remove', { file: s.file })));
    return card;
  }) : [el('p', 'none', 'None yet.')]));
  shots.append(tools, list);

  $('view-store').replaceChildren(head, status, graphics, shots);
  if (said) setStoreStatus(said, isError);
  renderStoreSide();
}

/// What Play asks for, and where it goes: Studio never uploads.
function renderStoreSide() {
  const d = storeData;
  const ready = d.shots.filter((s) => !s.problems.length).length;
  const need = (done, text) => el('li', done ? 'good' : 'bad', `${done ? 'Ready' : 'Missing'}: ${text}`);
  const list = el('ul', 'store-needs');
  list.append(
    need(d.graphics[0]?.current, 'app icon, 512×512'),
    need(d.graphics[1]?.current, 'feature graphic, 1024×500'),
    need(ready >= 2, `phone screenshots, at least 2 (${ready} ready)`),
  );
  $('side-plan').replaceChildren(
    el('h2', 'label', 'What Play asks for'),
    list,
    el('p', 'plan-note', 'Upload them yourself in Play Console: Grow users, Store presence, Store listings. Studio never uploads.'),
    el('p', 'note', `The files are in ${d.dir}, which git ignores.`),
  );
}

function setStoreStatus(text, isError = false) {
  const s = $('store-status');
  if (!s) return;
  s.textContent = text;
  s.style.color = isError ? 'var(--err)' : '';
}

async function storePost(action, body = {}) {
  const slug = state.slug;
  setStoreStatus(action === 'shot' ? 'Capturing the emulator screen…' : 'Working…');
  const { status: code, data } = await api(`/api/brands/${slug}/store/${action}`, body);
  if (slug !== state.slug || state.view !== 'store') return;
  if (code !== 200) {
    setStoreStatus(data.error ?? 'Studio could not do that', true);
    return;
  }
  storeData = data;
  drawStore({ shot: `Captured ${data.shots.at(-1)?.file ?? 'the screen'}.`, graphics: `Wrote both graphics to ${data.dir}.`, remove: 'Removed.' }[action]);
}

/// The Store's jobs (the build, capture mode; their lines are in Logs), started without leaving this tab.
async function storeJob(job) {
  const { status: code, data } = await api('/api/jobs', { job, slug: state.slug });
  if (code !== 200) {
    setStoreStatus(data.error ?? `Could not start ${job}`, true);
    return;
  }
  setStoreStatus({
    'build-store': 'Building the app as the store will show it: it opens on the emulator in a few minutes. Its lines are in Logs.',
    'store-capture-on': `Capture mode is starting: in a few seconds the emulator shows ${storeData.shotSize}. Open a screen, then press Capture.`,
    'store-capture-off': 'Capture mode is ending: the emulator goes back to its own size.',
  }[job]);
}
