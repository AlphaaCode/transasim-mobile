// SPC Studio: Backend (docs/STUDIO-SPEC.md §16). The brand's DEV backend,
// the read-only checker Alpha runs on the server, its pasted report, the
// items and the gate they hold, and Go phase 2. Studio never connects to a
// server: it prints commands and reads what is pasted back.
'use strict';

const be = { env: 'dev', data: null, edits: null, seq: 0, pseq: 0, timer: null, verdict: '' };
const BE_STATUS = {
  pass: ['pass', 'ok'], fail: ['fail', 'err'], stale: ['stale', 'err'], warn: ['warn', 'warn'],
  unknown: ['unknown', 'warn'], accepted: ['accepted', 'acc'], na: ['n/a', 'na'],
};
const BE_FIELDS = [
  ['server', 'Server', 'select'],
  ['name', 'Name on the box', 'acorn-backend: the folder, APP_NAME and systemd unit'],
  ['domain', 'Domain', 'acorn.transasim.com'],
  ['apiBaseUrl', 'API base URL', 'https://acorn.transasim.com/api'],
  ['port', 'Port', '9074'],
  ['dir', 'Folder', '/apps/acorn-backend'],
  ['db', 'Database', 'acorn_prod'],
  ['jar', 'Jar', 'acorn-backend.jar'],
  ['restartMethod', 'Restart method', 'select'],
  ['shellUser', 'Login', 'root'],
  ['stripePublishableKeyTest', 'Stripe pk_test_ key', 'only with payments: DEV builds use it'],
];

async function renderBackend(keepVerdict = false) {
  const slug = state.slug;
  const seq = ++be.seq;
  if (!keepVerdict) be.verdict = '';
  const { data } = await api(`/api/brands/${slug}/backend?env=${be.env}`);
  if (seq !== be.seq || state.view !== 'backend' || slug !== state.slug) return;
  be.data = data;
  be.edits = JSON.parse(JSON.stringify(data.backend ?? {}));
  drawBackend();
}

function drawBackend(focusId) {
  const d = be.data;
  const head = el('div', 'sheet-head');
  const envs = el('div', 'actions');
  for (const [env, label] of [['dev', 'DEV'], ['prod', 'PROD']]) {
    const b = el('button', 'ghost', label);
    b.type = 'button';
    b.setAttribute('aria-pressed', String(be.env === env));
    b.onclick = () => { be.env = env; renderBackend(); };
    envs.append(b);
  }
  const counts = (s) => d.items.filter((i) => i.status === s).length;
  const chips = el('div', 'chips');
  if (d.items.length) {
    chips.append(
      el('span', `chip ${counts('fail') + counts('stale') ? 'err' : 'ok'}`, `${counts('fail') + counts('stale')} failing`),
      el('span', `chip ${counts('warn') + counts('unknown') ? 'warn' : 'ok'}`, `${counts('warn') + counts('unknown')} to look at`),
      el('span', 'chip ok', `${counts('pass') + counts('accepted')} fine`));
  }
  head.append(el('h1', '', `Backend · ${current()?.name ?? state.slug}`), chips, envs);

  const said = el('p', 'toast be-verdict');
  said.id = 'be-status';
  said.setAttribute('role', 'status');
  said.textContent = be.verdict;
  $('view-backend').replaceChildren(head, gateTicket(d), said, fieldsSection(d), checkerSection(d), reportSection(d), itemsSection(d));
  // A redraw replaces every node: put the keyboard back on the control that caused it.
  if (focusId) document.getElementById(focusId)?.focus();
  previewBackend();
}

// ---- the gate ticket: what holds Go phase 2, and the button that opens it ----

function gateTicket(d) {
  if (d.legacy) return legacyTicket(d);
  if (be.env === 'prod') return prodTicket(d);
  const blockers = d.gates?.test ?? [];
  const phase2 = d.backend?.phase2;
  const ticket = el('section', `gate ${phase2 ? 'passed' : blockers.length || !d.items.length ? 'shut' : 'open'}`);
  ticket.setAttribute('aria-labelledby', 'gate-title');
  const main = el('div', 'gate-main');
  const title = el('h2', 'label', 'Gate test · Go phase 2');
  title.id = 'gate-title';
  main.append(title);
  if (phase2) {
    main.append(el('p', 'gate-big', 'Phase 2'),
      el('p', 'gate-sub', `Since ${phase2.at.slice(0, 16).replace('T', ' ')} UTC · jar ${phase2.jarSha256} · backend ${phase2.backendCommit}`));
  } else if (!d.items.length) {
    main.append(el('p', 'gate-big', 'Not yet'), el('p', 'gate-sub', d.error ?? 'Enter the DEV backend below.'));
  } else {
    main.append(el('p', 'gate-big', blockers.length ? `${blockers.length} blocking` : 'Open'));
    const list = el('ol', 'gate-list');
    for (const id of blockers) {
      const item = d.items.find((i) => i.id === id);
      const b = el('button', '', '');
      b.type = 'button';
      b.append(el('span', 'k', id), el('span', 'v', item?.reason ?? ''));
      b.onclick = () => {
        const row = document.getElementById(`item-${id}`);
        const det = row?.querySelector('details');
        if (det) det.open = true;
        row?.scrollIntoView({ block: 'center' });
        row?.querySelector('summary')?.focus();
      };
      const li = el('li');
      li.append(b);
      list.append(li);
    }
    if (blockers.length) main.append(list);
    else main.append(el('p', 'gate-sub', 'Every blocking DEV item passes. Probes must be from the last hour.'));
    // Probes live in memory: after a restart they are the usual blockers, so Check sits here too.
    if (blockers.some((id) => d.items.find((i) => i.id === id)?.reason.startsWith('not probed'))) {
      const probe = el('button', 'ghost get', 'Check (probe from this PC)');
      probe.type = 'button';
      probe.id = 'be-gate-probe';
      probe.onclick = () => runProbe(probe, 'be-gate-probe');
      main.append(probe);
    }
  }

  const stub = el('div', 'gate-stub');
  if (phase2) {
    const go = el('button', 'apply', 'Build for test (DEV)');
    go.type = 'button';
    go.onclick = () => showView('build');
    stub.append(go, el('p', 'note', 'A profile APK pointed at the DEV backend.'));
  } else {
    const label = el('label', '', 'Backend commit');
    label.htmlFor = 'be-commit';
    const commit = el('input');
    commit.id = 'be-commit';
    commit.type = 'text';
    commit.placeholder = '54dd318';
    commit.autocomplete = 'off';
    commit.spellcheck = false;
    const go = el('button', 'apply', 'Go phase 2');
    go.type = 'button';
    go.disabled = Boolean(blockers.length || !d.items.length);
    go.onclick = () => phase2Preview(commit.value.trim());
    stub.append(label, commit, go, el('p', 'note', 'Shows what it writes first. Records the DEV jar and this commit.'));
  }
  ticket.append(main, stub);
  return ticket;
}

/// A brand live before the backend phase: the items are there to read, and
/// nothing waits on them.
function legacyTicket(d) {
  const ticket = el('section', 'gate legacy');
  ticket.setAttribute('aria-labelledby', 'gate-title');
  const main = el('div', 'gate-main');
  const title = el('h2', 'label', 'Legacy brand · information only');
  title.id = 'gate-title';
  const name = current()?.name ?? state.slug;
  main.append(title, el('p', 'gate-big', 'No gate'),
    el('p', 'gate-sub', `${name} was live before the backend phase. Its backend items are shown as they are and never block a build or a release.`));
  const stub = el('div', 'gate-stub');
  const go = el('button', 'apply', 'Build for test (DEV)');
  go.type = 'button';
  go.disabled = !d.backend?.dev?.apiBaseUrl;
  go.onclick = () => showView('build');
  stub.append(go, el('p', 'note', go.disabled ? 'Enter the DEV backend first.' : 'A profile APK pointed at the DEV backend.'));
  ticket.append(main, stub);
  return ticket;
}

/// PROD's ticket: what holds Go prod, then, once on PROD, what a release still waits on.
function prodTicket(d) {
  const onProd = d.activeEnv === 'prod';
  const open = onProd ? d.releaseCheck : d.goProd.map((b) => `${b.id}: ${b.reason}`);
  const ticket = el('section', `gate ${open.length ? 'shut' : onProd ? 'passed' : 'open'}`);
  ticket.setAttribute('aria-labelledby', 'gate-title');
  const main = el('div', 'gate-main');
  const title = el('h2', 'label', onProd ? 'Release check' : 'Gate release · Go prod');
  title.id = 'gate-title';
  main.append(title, el('p', 'gate-big', open.length ? `${open.length} blocking` : onProd ? 'Release ready' : 'Open'));
  if (onProd) main.append(el('p', 'gate-sub', `On PROD since ${String(d.backend.prodAt ?? '').slice(0, 16).replace('T', ' ')} UTC.`));
  const list = el('ol', 'gate-list');
  for (const line of open) {
    const [id, ...rest] = line.split(': ');
    const b = el('button', '', '');
    b.type = 'button';
    b.append(el('span', 'k', id), el('span', 'v', rest.join(': ')));
    b.onclick = () => {
      const row = document.getElementById(`item-${id}`);
      const det = row?.querySelector('details');
      if (det) det.open = true;
      row?.scrollIntoView({ block: 'center' });
      row?.querySelector('summary')?.focus();
    };
    const li = el('li');
    li.append(b);
    list.append(li);
  }
  if (open.length) main.append(list);
  if (open.some((l) => l.startsWith('probes') || l.includes('not probed'))) {
    const probe = el('button', 'ghost get', 'Check (probe from this PC)');
    probe.type = 'button';
    probe.id = 'be-gate-probe';
    probe.onclick = () => runProbe(probe, 'be-gate-probe');
    main.append(probe);
  }
  const stub = el('div', 'gate-stub');
  if (onProd) {
    stub.append(el('p', 'note', 'Slice E builds the release, and asks this check first.'));
  } else {
    let key = null;
    if (d.features.payments) {
      const label = el('label', '', 'pk_live_ key');
      label.htmlFor = 'be-pk-live';
      key = el('input');
      key.id = 'be-pk-live';
      key.type = 'text';
      key.autocomplete = 'off';
      key.spellcheck = false;
      stub.append(label, key);
    }
    const go = el('button', 'apply', 'Go prod');
    go.type = 'button';
    go.disabled = Boolean(d.goProd.length);
    go.onclick = () => goProdPreview(key?.value.trim() || undefined);
    stub.append(go, el('p', 'note', "Shows its diff first: brand.json's apiBaseUrl becomes PROD's. Never commits."));
  }
  ticket.append(main, stub);
  return ticket;
}

async function goProdPreview(stripeKeyLive, dirty) {
  const slug = state.slug;
  const { data } = await api(`/api/brands/${slug}/backend/goprod/preview`, { stripeKeyLive });
  renderPlan(data, {
    title: 'Go prod',
    applyLabel: 'Go prod',
    dirty,
    onApply: async (accepted) => {
      const r = await api(`/api/brands/${slug}/backend/goprod/apply`, { stripeKeyLive, acceptDirty: accepted });
      if (r.status === 409) return goProdPreview(stripeKeyLive, r.data.dirty);
      if (r.status !== 200) return planStatus(r.data.refused || r.data.error, true);
      await load(slug);
      await renderBackend();
      planStatus("brand.json now points at PROD. Review and commit when ready.");
    },
  });
}

async function phase2Preview(commit, dirty) {
  const slug = state.slug;
  const { data } = await api(`/api/brands/${slug}/backend/phase2/preview`, { commit });
  renderPlan(data, {
    title: 'Go phase 2',
    applyLabel: 'Go phase 2',
    dirty,
    onApply: async (accepted) => {
      const r = await api(`/api/brands/${slug}/backend/phase2/apply`, { commit, acceptDirty: accepted });
      if (r.status === 409) return phase2Preview(commit, r.data.dirty);
      if (r.status !== 200) return planStatus(r.data.refused || r.data.error, true);
      await load(slug);
      await renderBackend();
      planStatus('Phase 2 recorded in studio.json. Review and commit when ready.');
    },
  });
}

// ---- 1. the backend's fields --------------------------------------------------

function fieldsSection(d) {
  const sec = el('section', 'be-section');
  sec.append(el('h2', 'label', `1 · The ${be.env.toUpperCase()} backend`));
  const cfg = (be.edits[be.env] ??= {});
  const form = el('div', 'be-form');
  for (const [key, label, hint] of BE_FIELDS) {
    if (key === 'stripePublishableKeyTest' && be.env !== 'dev') continue;
    const id = `be-f-${key}`;
    const row = el('div', 'field');
    row.dataset.path = `backend.${be.env}.${key}`;
    const lab = el('label', 'key', label);
    lab.htmlFor = id;
    const control = el('div', 'control');
    let input;
    if (hint === 'select') {
      input = el('select');
      const options = key === 'server'
        ? d.servers.filter((s) => s.role !== 'retired').map((s) => [s.id, `${s.id} · ${s.host} · ${s.role}${s.prodFor.length ? ` (production of ${s.prodFor.join(', ')})` : ''}`])
        : [['scripts', 'scripts: bin/shutdown.sh, then bin/startup.sh'], ['systemd', 'systemd: systemctl restart']];
      input.append(el('option', '', '—'), ...options.map(([v, t]) => { const o = el('option', '', t); o.value = v; return o; }));
      input.value = cfg[key] ?? '';
    } else {
      input = el('input');
      input.type = 'text';
      input.placeholder = hint;
      input.value = cfg[key] ?? '';
      input.spellcheck = false;
      input.autocomplete = 'off';
    }
    input.id = id;
    input.oninput = input.onchange = () => {
      const v = input.value.trim();
      if (!v) delete cfg[key];
      else cfg[key] = key === 'port' && /^\d+$/.test(v) ? Number(v) : v;
      schedulePreview();
    };
    control.append(input);
    row.append(lab, control);
    form.append(row);
  }

  // What the brand has: two declared, the rest derived from brand.json and the
  // repo. A legacy brand is never asked: Studio reads both from the app.
  const features = d.legacy ? {} : (be.edits.features ??= {});
  for (const [key, label] of d.legacy ? [] : [['payments', 'Takes payments'], ['vouchers', 'Redeems vouchers']]) {
    const id = `be-feat-${key}`;
    const row = el('div', 'field');
    row.dataset.path = `backend.features.${key}`;
    const lab = el('label', 'key', label);
    lab.htmlFor = id;
    const s = el('select');
    s.id = id;
    for (const [v, t] of [['', 'not declared'], ['true', 'yes'], ['false', 'no']]) { const o = el('option', '', t); o.value = v; s.append(o); }
    s.value = features[key] === undefined ? '' : String(features[key]);
    s.onchange = () => {
      if (s.value === '') delete features[key]; else features[key] = s.value === 'true';
      schedulePreview();
    };
    const control = el('div', 'control');
    control.append(s);
    row.append(lab, control);
    form.append(row);
  }
  const yes = (v) => (v ? 'yes' : 'no');
  const derived = el('p', 'plan-note', [
    ...(d.legacy ? [`payments ${yes(d.features.payments)} (brand.json's key)`, `vouchers ${yes(d.features.vouchers)} (the app offers them)`] : []),
    `Google sign-in ${yes(d.features.google)} (brand.json)`,
    `iOS ${yes(d.features.ios)} (the app offers Sign in with Apple there)`,
    'provisions eSIMs yes',
  ].join(', ').replace(/^/, 'Derived: ') + '.');

  form.append(textRow('clientDomains', "Client's own domains", 'odysseysim.com, comma-separated',
    (be.edits.clientDomains ?? []).join(', '),
    (v) => { const list = v.split(',').map((x) => x.trim()).filter(Boolean); if (list.length) be.edits.clientDomains = list; else delete be.edits.clientDomains; }));
  form.append(textRow('migrationPath', 'Migration path', 'SQL files applied by deploy.sh', be.edits.migrationPath ?? '',
    (v) => { if (v) be.edits.migrationPath = v; else delete be.edits.migrationPath; }));
  const accepted = Object.entries(be.edits.schemaAccepted ?? {}).map(([k, v]) => `${k}: ${v}`).join('\n');
  form.append(textRow('schemaAccepted', 'Accepted CHECK differences', 'table.check_name: why it is accepted, one per line', accepted, (v) => {
    const map = {};
    for (const line of v.split('\n')) {
      const i = line.indexOf(':');
      if (i > 0) map[line.slice(0, i).trim()] = line.slice(i + 1).trim();
    }
    if (Object.keys(map).length) be.edits.schemaAccepted = map; else delete be.edits.schemaAccepted;
  }, true));
  sec.append(form, derived, ledgerEditor());
  return sec;
}

/// The schema ledger: every SQL run by hand on DEV, ticked when it is applied on PROD.
function ledgerEditor() {
  const ledger = (be.edits.schemaLedger ??= []);
  const box = el('div', 'be-ledger');
  box.append(el('h3', 'be-group', 'Schema ledger: SQL run by hand on DEV'));
  if (!ledger.length) box.append(el('p', 'note', 'Nothing recorded. Go prod waits on every entry being applied on PROD.'));
  const today = new Date().toISOString().slice(0, 10);
  ledger.forEach((e, i) => {
    const row = el('div', 'be-tick');
    const done = el('input');
    done.type = 'checkbox';
    done.id = `ledger-${i}`;
    done.checked = Boolean(e.prodAt);
    done.onchange = () => { if (done.checked) e.prodAt = today; else delete e.prodAt; schedulePreview(); };
    const lab = el('label', '', `${e.what} (DEV ${e.devAt}${e.prodAt ? `, PROD ${e.prodAt}` : ''})`);
    lab.htmlFor = done.id;
    const drop = el('button', 'ghost copy', 'Remove');
    drop.type = 'button';
    drop.onclick = () => { ledger.splice(i, 1); drawBackend(); };
    row.append(done, lab, drop);
    box.append(row);
  });
  const add = el('div', 'be-tick');
  const what = el('input');
  what.type = 'text';
  what.id = 'ledger-what';
  what.placeholder = 'acorn_prod: app_config.config_key, updated_by, subscriber.auth_provider to varchar(255)';
  const lab = el('label', '', 'What the SQL did');
  lab.htmlFor = what.id;
  const go = el('button', 'ghost', 'Add an entry (run on DEV today)');
  go.type = 'button';
  go.onclick = () => {
    const text = what.value.trim();
    if (!text) return;
    const id = text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40) || `sql-${ledger.length + 1}`;
    ledger.push({ id: ledger.some((e) => e.id === id) ? `${id}-${ledger.length + 1}` : id, what: text, devAt: today });
    drawBackend();
  };
  add.append(lab, what, go);
  box.append(add);
  return box;
}

function textRow(key, label, hint, value, set, multiline = false) {
  const id = `be-f-${key}`;
  const row = el('div', 'field');
  row.dataset.path = `backend.${key}`;
  const lab = el('label', 'key', label);
  lab.htmlFor = id;
  const input = el(multiline ? 'textarea' : 'input');
  if (!multiline) input.type = 'text';
  input.id = id;
  input.placeholder = hint;
  input.value = value;
  input.spellcheck = false;
  input.oninput = () => { set(input.value.trim()); schedulePreview(); };
  const control = el('div', 'control');
  control.append(input);
  row.append(lab, control);
  return row;
}

function schedulePreview() {
  clearTimeout(be.timer);
  be.timer = setTimeout(previewBackend, 300);
}

async function previewBackend(acceptDirty, ticks) {
  if (state.view !== 'backend') return;
  const slug = state.slug;
  const seq = ++be.pseq;
  const { data } = await api(`/api/brands/${slug}/backend/preview`, { backend: be.edits, ticks });
  if (seq !== be.pseq || slug !== state.slug || state.view !== 'backend') return;
  for (const row of document.querySelectorAll('#view-backend .be-form .field')) {
    const err = data.errors.find((e) => e.field === row.dataset.path);
    row.classList.toggle('err', Boolean(err));
    let msg = row.querySelector('.msg');
    if (err && !msg) { msg = el('p', 'msg'); row.append(msg); }
    if (msg) msg.textContent = err?.reason ?? '';
  }
  renderPlan(data, {
    title: `Backend · ${current()?.name ?? slug}`,
    applyLabel: 'Apply',
    dirty: Array.isArray(acceptDirty) ? acceptDirty : undefined,
    onApply: async (accepted) => {
      const r = await api(`/api/brands/${slug}/backend/apply`, { backend: be.edits, ticks, acceptDirty: accepted });
      if (r.status === 409) return previewBackend(r.data.dirty, ticks);
      if (r.status !== 200) return planStatus(r.data.refused || r.data.error, true);
      await load(slug);
      await renderBackend();
      planStatus(`Wrote ${r.data.written.length} file${r.data.written.length === 1 ? '' : 's'}. Review and commit when ready.`);
    },
  });
}

// ---- 2. the checker, and the commands for this backend ---------------------------

function copyButton(text, label = 'Copy') {
  const b = el('button', 'ghost copy', label);
  b.type = 'button';
  b.onclick = async () => {
    try { await navigator.clipboard.writeText(text); b.textContent = 'Copied'; }
    catch { b.textContent = 'Copy failed: select the text'; }
    $('be-status').textContent = b.textContent === 'Copied' ? 'Copied to the clipboard.' : 'Copy failed: select the text and copy it.';
    setTimeout(() => { b.textContent = label; }, 1500);
  };
  return b;
}

function checkerSection(d) {
  const sec = el('section', 'be-section');
  sec.append(el('h2', 'label', '2 · Run the checker on the server'),
    el('p', 'plan-note', 'Read-only. It prints one JSON line of booleans, counts and hashes, and withholds everything if a secret-shaped value shows up. Studio never connects: you log in and run it.'));
  const files = el('ul', 'be-files');
  for (const f of d.checker.files) {
    const li = el('li');
    li.append(el('span', 'k', f.name), el('span', 'v', f.sha256));
    files.append(li);
  }
  const install = el('details', 'file');
  install.append(el('summary', '', 'Install once: writes the three files to ~/spc-check and prints their SHA-256'));
  const pre = el('pre', 'be-cmd');
  pre.textContent = d.checker.install;
  install.append(pre, copyButton(d.checker.install, 'Copy the install paste'));
  sec.append(files, install);
  const book = el('details', 'file');
  book.append(el('summary', '', `The ${be.env.toUpperCase()} runbook: every step, generated from the same items as the checklist`));
  book.addEventListener('toggle', async () => {
    if (!book.open || book.dataset.loaded) return;
    const { data } = await api(`/api/brands/${state.slug}/backend/runbook?env=${be.env}`);
    const pre = el('pre', 'be-cmd be-runbook');
    pre.textContent = data.text;
    book.append(pre, copyButton(data.text, 'Copy the runbook'));
    book.dataset.loaded = '1';
  });
  sec.append(book);
  if (!d.commands.length) sec.append(el('p', 'none', 'The commands appear once the server and folder are entered.'));
  for (const c of d.commands) {
    const box = el('div', 'be-command');
    const pre = el('pre', 'be-cmd');
    pre.textContent = c.text;
    box.append(el('p', 'be-command-title', c.title), pre, copyButton(c.text));
    sec.append(box);
  }
  return sec;
}

// ---- 3. the report -------------------------------------------------------------

function reportSection(d) {
  const sec = el('section', 'be-section');
  sec.append(el('h2', 'label', '3 · Paste its report'));
  const r = d.report;
  sec.append(el('p', `plan-note ${r && !r.fresh ? 'stale' : ''}`, r
    ? `Last report: ${r.hostname}, ${r.at.slice(0, 16).replace('T', ' ')} UTC${r.fresh ? '' : ' · older than 24 h: run the checker again'} · jar ${r.jar} · restarts by ${r.restartMethod}`
    : 'No report yet.'));
  const lab = el('label', 'sr-only', "The checker's JSON line");
  lab.htmlFor = 'be-report';
  const box = el('textarea', 'bundle be-report');
  box.id = 'be-report';
  box.placeholder = '{"hostname": "vmi3448057", "schema_version": 1, …}';
  box.spellcheck = false;
  const go = el('button', 'apply', 'Check the report');
  go.id = 'be-check-report';
  go.type = 'button';
  go.onclick = async () => {
    const { status, data } = await api(`/api/brands/${state.slug}/backend/report`, { env: be.env, text: box.value });
    if (status === 200) {
      be.verdict = `Accepted: report from ${data.report?.hostname}. Stored under .studio/reports (never committed).`;
      be.data = data;
      drawBackend('be-check-report');
    } else {
      // Refused: the text is cleared, since it may hold what was refused.
      box.value = '';
      be.verdict = data.refused || data.error;
      $('be-status').textContent = be.verdict;
      $('be-status').classList.add('refused');
    }
  };
  sec.append(lab, box, go);
  if (state.slug === d.reference.brand) {
    const ref = el('button', 'ghost', 'Use as schema reference');
    ref.type = 'button';
    ref.onclick = () => referencePreview();
    sec.append(ref, el('p', 'note', d.reference.exists
      ? `Reference from ${d.reference.generatedAt}. Every brand's schema is compared with it.`
      : 'No reference yet: every brand\'s schema drift reads unknown until this is pressed.'));
  }
  return sec;
}

async function referencePreview(dirty) {
  const slug = state.slug;
  const { data } = await api(`/api/brands/${slug}/backend/reference/preview`, {});
  renderPlan(data, {
    title: 'Schema reference',
    applyLabel: 'Write the reference',
    dirty,
    onApply: async (accepted) => {
      const r = await api(`/api/brands/${slug}/backend/reference/apply`, { acceptDirty: accepted });
      if (r.status === 409) return referencePreview(r.data.dirty);
      if (r.status !== 200) return planStatus(r.data.refused || r.data.error, true);
      await renderBackend();
      planStatus('Wrote the reference. Review and commit when ready.');
    },
  });
}

// ---- 4. the items -----------------------------------------------------------------

function itemsSection(d) {
  const sec = el('section', 'be-section');
  const head = el('div', 'be-items-head');
  const probe = el('button', 'ghost get', 'Check (probe from this PC)');
  probe.id = 'be-probe';
  probe.type = 'button';
  probe.onclick = () => runProbe(probe, 'be-probe');
  head.append(el('h2', 'label', '4 · Items'), probe,
    el('span', 'note', d.probesAt ? `Probed ${d.probesAt.slice(11, 16)} UTC` : 'Not probed this session'));
  sec.append(head);
  if (d.error) sec.append(el('p', 'none', d.error));
  for (const [title, test] of [['Server, shared by every backend on it', (i) => i.env === 'server'], ['This backend', (i) => i.env !== 'server']]) {
    const group = d.items.filter(test);
    if (!group.length) continue;
    const list = el('ul', 'checks be-items');
    for (const i of group) list.append(itemRow(i));
    sec.append(el('h3', 'be-group', title), list);
  }
  return sec;
}

async function runProbe(button, focusId) {
  button.disabled = true;
  button.textContent = 'Probing…';
  $('be-status').textContent = 'Probing DNS, TLS, the catalogue and the sign-in endpoints…';
  const { status, data } = await api(`/api/brands/${state.slug}/backend/probe`, { env: be.env });
  if (status === 200) { be.data = data; be.verdict = 'Probed.'; drawBackend(focusId); }
  else { button.disabled = false; button.textContent = 'Check (probe from this PC)'; $('be-status').textContent = data.error; }
}

function itemRow(i) {
  const [label, cls] = BE_STATUS[i.status] ?? [i.status, 'na'];
  const li = el('li', `be-item ${cls}`);
  li.id = `item-${i.id}`;
  const det = el('details');
  const sum = el('summary');
  sum.append(el('span', 'st', label), el('span', 'id', i.id), el('span', 'k', i.title), el('span', 'v', i.reason),
    el('span', 'g', `${i.gate}${i.severity === 'warn' ? ' · warns' : ''}`));
  det.append(sum);
  const body = el('div', 'be-item-body');
  body.append(el('p', '', i.cause), el('p', 'fix', `Fix: ${i.fix}`));
  if (i.acceptedRisk) body.append(el('p', 'meta', `Accepted risk: ${i.acceptedRisk}`));
  if (i.kind === 'checklist' && i.status !== 'na') body.append(tickForm(i));
  if (i.id === 'be-schema-drift' && be.data.schemaChecks?.length) body.append(acceptChecks(be.data.schemaChecks));
  det.append(body);
  li.append(det);
  return li;
}

/// Accepting CHECK differences where they block, not only in the fields
/// above: one reason for all of them, written through the previewed Apply.
function acceptChecks(names) {
  const box = el('div', 'be-tick be-accept');
  const reason = el('input');
  reason.type = 'text';
  reason.id = 'be-accept-reason';
  reason.value = "Liquibase schema adds no enum CHECK; the backend's enum sets the value";
  const lab = el('label', '', `Accept these ${names.length} CHECK difference${names.length === 1 ? '' : 's'}, because`);
  lab.htmlFor = reason.id;
  const go = el('button', 'ghost get', 'Preview accepting them');
  go.type = 'button';
  go.onclick = () => {
    const why = reason.value.trim();
    if (!why) { $('be-status').textContent = 'Say why they are accepted.'; return; }
    be.edits.schemaAccepted = { ...(be.edits.schemaAccepted ?? {}), ...Object.fromEntries(names.map((n) => [n, why])) };
    previewBackend();
    $('be-status').textContent = `${names.length} accepted in the preview: Apply in the side panel writes studio.json.`;
  };
  box.append(lab, reason, go, el('p', 'meta', names.join(', ')));
  return box;
}

function tickForm(i) {
  const form = el('div', 'be-tick');
  const note = el('input');
  note.type = 'text';
  note.id = `tick-${i.id}`;
  note.placeholder = 'What was done, and what shows it worked';
  const lab = el('label', '', 'Tick with a note');
  lab.htmlFor = note.id;
  const go = el('button', 'ghost', 'Preview the tick');
  go.type = 'button';
  go.onclick = () => previewBackend(undefined, { [i.id]: { note: note.value, evidence: '' } });
  form.append(lab, note, go);
  return form;
}
