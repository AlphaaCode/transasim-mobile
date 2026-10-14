// SPC Studio: Build, Logs and the jobs panel. The server runs one job at a
// time; this page starts jobs by name, follows one live, and for a failure
// shows what it matched in the incident list and the Fix Bundle for Claude.
'use strict';

const run = {
  jobs: [],
  names: {},
  open: null,     // the job (or earlier log) the Logs view shows
  lines: [],
  paused: false,
  query: '',
  source: null,   // the EventSource following run.open
  bundle: null,   // {id, text} once shown
  earlier: [],
};

// How a line is coloured, first match wins. Text labels carry the same
// meaning for anyone who cannot tell the colours apart: see .ln::before.
const LEVELS = [
  [/^\$ /, 'cmd'],
  [/^\[studio\] /, 'studio'],
  // flutter test's progress lines name tests ("…names itself in the error"):
  // only one flutter marks [E] failed.
  [/^\d\d:\d\d \+\d+.*\[E\]\s*$|Some tests failed/, 'err'],
  [/^\d\d:\d\d \+\d+/, ''],
  [/(^|\s)E\/|\berror\b|exception|FAILURE|FAILED|\bfatal\b/i, 'err'],
  [/(^|\s)W\/|\bwarning\b/i, 'warn'],
];
const levelOf = (line) => (LEVELS.find(([re]) => re.test(line)) ?? [null, ''])[1];
const MAX_LINES = 10000; // the full log is on disk; the page keeps the last ones

const openJob = () => run.jobs.find((j) => j.id === run.open);
const seconds = (ms) => (ms == null ? '' : `${(ms / 1000).toFixed(1)} s`);

async function refreshJobs() {
  const { data } = await api('/api/jobs');
  run.jobs = data.jobs;
  run.names = data.names;
  run.proposals = (await api('/api/cases/proposals')).data;
  renderJobsSide();
}

/// [fixOf]: the failed job whose card the autofix button was pressed on.
async function startJob(job, slug = 'studio', fixOf) {
  const { status: code, data } = await api('/api/jobs', { job, slug, fixOf });
  if (code !== 200) {
    announce(data.error ?? `Could not start ${job}`, true);
    return;
  }
  await refreshJobs();
  follow(data.id);
  showView('logs');
  // The button pressed is now hidden: keep the keyboard on the new log.
  $('log-lines')?.focus();
}

/// Shows job [id]: the lines so far, then the new ones as they arrive.
function follow(id) {
  run.source?.close();
  Object.assign(run, { open: id, lines: [], bundle: null });
  const source = new EventSource(`/api/jobs/${encodeURIComponent(id)}/stream`);
  run.source = source;
  let first = true;
  source.onmessage = (e) => {
    if (first) { first = false; refreshJobs(); }
    addLine(e.data);
  };
  source.addEventListener('end', (e) => {
    source.close();
    const job = JSON.parse(e.data);
    run.jobs = run.jobs.map((j) => (j.id === job.id ? job : j));
    const found = job.matched.length ? `, ${job.matched.length} known incident${job.matched.length > 1 ? 's' : ''} found` : '';
    announce(`${run.names[job.name] ?? job.name}: ${job.state}${job.exitCode == null ? '' : ` (exit ${job.exitCode})`}${found}`,
      job.state === 'failed');
    refreshJobs();
    if (state.view === 'logs') renderLogHead();
  });
  source.onerror = () => { if (source.readyState === EventSource.CLOSED) refreshJobs(); };
  if (state.view === 'logs') renderLogs();
}

async function openEarlier(name) {
  run.source?.close();
  const { data } = await api(`/api/logs/${encodeURIComponent(name)}`);
  Object.assign(run, { open: `log:${name}`, lines: data.text.split('\n'), bundle: null });
  renderLogs();
  renderJobsSide();
}

function addLine(line) {
  run.lines.push(line);
  if (run.lines.length > MAX_LINES) run.lines.splice(0, run.lines.length - MAX_LINES);
  if (state.view !== 'logs' || run.paused) return;
  const box = $('log-lines');
  if (!box) return;
  if (!run.query || line.toLowerCase().includes(run.query)) {
    const atEnd = box.scrollTop + box.clientHeight >= box.scrollHeight - 24;
    box.append(lineNode(line));
    if (box.childElementCount > MAX_LINES) box.firstElementChild.remove();
    if (atEnd) box.scrollTop = box.scrollHeight;
  }
  renderCounts();
}

function lineNode(line) {
  const level = levelOf(line);
  const n = el('div', `ln ${level}`, line);
  if (level === 'err' || level === 'warn') n.dataset.level = level === 'err' ? 'error' : 'warning';
  return n;
}

function renderCounts() {
  const c = $('log-counts');
  if (!c) return;
  const errors = run.lines.filter((l) => levelOf(l) === 'err').length;
  const warns = run.lines.filter((l) => levelOf(l) === 'warn').length;
  c.replaceChildren(
    el('span', `chip ${errors ? 'err' : 'ok'}`, `${errors} error line${errors === 1 ? '' : 's'}`),
    el('span', `chip ${warns ? 'warn' : 'ok'}`, `${warns} warning${warns === 1 ? '' : 's'}`),
    el('span', 'chip', `${run.lines.length} lines`),
  );
}

// ---- Logs view --------------------------------------------------------------

function renderLogs() {
  const view = $('view-logs');
  const head = el('div', 'sheet-head');
  head.id = 'log-head';
  const tools = el('div', 'log-tools');
  const search = document.createElement('input');
  search.type = 'search';
  search.id = 'log-search';
  search.placeholder = 'Filter lines';
  search.value = run.query;
  search.oninput = () => { run.query = search.value.trim().toLowerCase(); renderLines(); };
  const searchLabel = el('label', 'sr-only', 'Filter the log');
  searchLabel.htmlFor = 'log-search';
  const pause = el('button', 'ghost', run.paused ? 'Resume' : 'Pause');
  pause.type = 'button';
  pause.setAttribute('aria-pressed', String(run.paused));
  pause.onclick = () => {
    run.paused = !run.paused;
    pause.textContent = run.paused ? 'Resume' : 'Pause';
    pause.setAttribute('aria-pressed', String(run.paused));
    if (!run.paused) renderLines();
  };
  const end = el('button', 'ghost', 'Jump to end');
  end.type = 'button';
  end.onclick = () => { const b = $('log-lines'); b.scrollTop = b.scrollHeight; };
  tools.append(searchLabel, search, pause, end);
  head.append(el('h1', '', 'Logs'), el('div', 'chips'), tools);
  const counts = el('div', 'chips log-counts');
  counts.id = 'log-counts';
  const box = el('div', 'log');
  box.id = 'log-lines';
  // A log, but not read aloud line by line: the end of a job is announced.
  box.setAttribute('role', 'log');
  box.setAttribute('aria-live', 'off');
  box.setAttribute('aria-label', 'Job output');
  box.tabIndex = 0;
  const said = el('p', 'toast log-status');
  said.id = 'log-status';
  said.setAttribute('role', 'status');
  view.replaceChildren(head, counts, said, run.open ? box : el('p', 'none', 'No job yet. Start one from Build or Doctor.'),
    classifyBox());
  renderLogHead();
  renderLines();
}

/// A server log pasted in (Studio never reads a server's logs itself): redacted,
/// matched against the incident list, and never stored.
function classifyBox() {
  const det = el('details', 'file classify');
  det.append(el('summary', '', 'Classify a pasted server log'));
  const lab = el('label', 'sr-only', 'Pasted log');
  lab.htmlFor = 'classify-text';
  const text = el('textarea', 'bundle');
  text.id = 'classify-text';
  text.placeholder = 'Paste lines from a backend log, certbot, nginx -t or the shell';
  const go = el('button', 'ghost get', 'Classify');
  go.type = 'button';
  const out = el('div', 'classify-out');
  out.setAttribute('role', 'status');
  go.onclick = async () => {
    const { data } = await api('/api/classify', { text: text.value });
    text.value = '';
    out.replaceChildren(...(data.length ? data.map((i) => {
      const card = el('div', 'incident');
      card.append(el('h3', '', i.title), el('p', 'line', i.line), el('p', '', i.cause), el('p', 'fix', `Fix: ${i.fix}`), el('p', 'meta', i.id));
      return card;
    }) : [el('p', 'none', 'No known incident in it: this may be a new one.')]));
  };
  det.append(lab, text, go, out);
  return det;
}

function renderLogHead() {
  const chips = document.querySelector('#log-head .chips');
  if (!chips) return;
  const job = openJob();
  const name = run.open?.startsWith('log:') ? run.open.slice(4) : job ? (run.names[job.name] ?? job.name) : '';
  chips.replaceChildren(
    ...(name ? [el('span', 'chip', name)] : []),
    ...(job ? [el('span', `chip ${{ passed: 'ok', failed: 'err', cancelled: 'warn' }[job.state] ?? ''}`, job.state)] : []),
  );
}

function renderLines() {
  const box = $('log-lines');
  if (!box) return;
  const shown = run.query ? run.lines.filter((l) => l.toLowerCase().includes(run.query)) : run.lines;
  box.replaceChildren(...shown.map(lineNode));
  box.scrollTop = box.scrollHeight;
  renderCounts();
}

function announce(text, isError = false) {
  const s = $('log-status') ?? $('build-status');
  if (!s) return;
  s.textContent = text;
  s.style.color = isError ? 'var(--err)' : '';
}

// ---- Build view ---------------------------------------------------------------

function renderBuild() {
  const slug = state.slug;
  const head = el('div', 'sheet-head');
  head.append(el('h1', '', current()?.name ?? slug), el('div', 'chips'));
  const card = el('section', 'job-card');
  card.append(el('h2', 'label', 'Validate'),
    el('p', 'plan-note', 'Runs on this machine, one job at a time, and writes a log under .studio/logs. Never commits, never pushes.'));
  for (const name of ['validate-fast', 'validate-full']) {
    const row = el('div', 'job-row');
    const go = el('button', 'apply', name === 'validate-fast' ? 'Validate (fast)' : 'Validate (full)');
    go.type = 'button';
    go.onclick = () => startJob(name, slug);
    const last = run.jobs.find((j) => j.name === name && j.slug === slug);
    row.append(go, el('p', 'note', run.names[name] ?? ''),
      ...(last ? [el('p', `note last ${last.state}`, `Last: ${last.state}${last.ms ? `, ${seconds(last.ms)}` : ''}`)] : []));
    card.append(row);
  }
  // A test build pointed at the brand's DEV backend, once Go phase 2 has passed.
  const dev = el('section', 'job-card');
  const legacy = state.studio[slug]?.backendGate === 'legacy';
  const phase2 = state.studio[slug]?.backend?.phase2 || (legacy && state.studio[slug]?.backend?.dev?.apiBaseUrl);
  dev.append(el('h2', 'label', 'Test on DEV'),
    el('p', 'plan-note', phase2
      ? `One press: a profile APK with API_BASE_URL set to the DEV backend${state.studio[slug].backend.dev?.stripePublishableKeyTest ? ' and its pk_test_ key' : ''}, then Gradle stops, the emulator starts, and the app is installed and opened. Never a release.${legacy ? ' A legacy brand: no gate.' : ''}`
      : 'Locked until Go phase 2, in the Backend tab: the DEV backend must pass its gate first.'));
  const row = el('div', 'job-row');
  const go = el('button', 'apply', 'Build for test (DEV)');
  go.type = 'button';
  go.disabled = !phase2;
  go.onclick = () => startJob('build-dev', slug);
  const last = run.jobs.find((j) => j.name === 'build-dev' && j.slug === slug);
  row.append(go, el('p', 'note', run.names['build-dev'] ?? ''),
    ...(last ? [el('p', `note last ${last.state}`, `Last: ${last.state}${last.ms ? `, ${seconds(last.ms)}` : ''}`)] : []));
  dev.append(row);
  // The emulator: one heavy process at a time, so Launch stops Gradle first.
  for (const [job, label, cls] of [['launch-dev', 'Launch again (no build)', 'ghost'], ['logcat', 'Watch logcat', 'ghost'], ['gradle-stop', 'Stop Gradle', 'ghost']]) {
    const r = el('div', 'job-row');
    const b = el('button', cls, label);
    b.type = 'button';
    if (job === 'launch-dev') b.disabled = !phase2;
    if (job === 'logcat') b.title = 'The app errors and flutter lines, once it runs on the emulator. Cancel it in Logs.';
    b.onclick = () => startJob(job, slug);
    const prev = run.jobs.find((j) => j.name === job && j.slug === slug);
    r.append(b, el('p', 'note', run.names[job] ?? ''),
      ...(prev ? [el('p', `note last ${prev.state}`, `Last: ${prev.state}${prev.ms ? `, ${seconds(prev.ms)}` : ''}`)] : []));
    dev.append(r);
  }
  const cases = el('section', 'job-card');
  cases.id = 'cases-card';
  const tested = el('section', 'job-card');
  tested.id = 'tested-card';
  const release = el('section', 'job-card');
  release.id = 'release-card';
  release.append(el('h2', 'label', 'Release (Android)'), el('p', 'note', 'Reading the release check…'));
  const ios = el('section', 'job-card');
  ios.id = 'ios-card';
  const said = el('p', 'toast');
  said.id = 'build-status';
  said.setAttribute('role', 'status');
  $('view-build').replaceChildren(head, card, dev, tested, release, ios, cases, said);
  fillRelease(slug);
  renderBuildCases();
}

/// The case store: how many cases there are, and the one-time seed (a dry run until Apply).
async function renderBuildCases() {
  const card = $('cases-card');
  if (!card) return;
  const { data } = await api('/api/cases');
  const seed = el('button', 'ghost', 'Seed from the incident list and fix commits');
  seed.type = 'button';
  seed.onclick = () => previewCases('seed', {}, 'Seed the case store', 'Store the seed');
  card.replaceChildren(el('h2', 'label', 'Case store'),
    el('p', 'plan-note', `${data.length} case${data.length === 1 ? '' : 's'}. A case is saved when a fix works, then Solve shows the nearest ones when a job fails. `
      + 'Seeding adds one case per incident and per "fix" commit; it writes nothing until you press Apply on the preview.'),
    seed);
}

/// "Tested on device/emulator": the result Alpha records after trying the brand by hand.
/// A release needs a Pass or a Skip for this commit and this brand. Recording is a
/// previewed Apply of brands/<slug>/studio.json, like every other write.
let lastTested = null;
const emu = { status: 'idle', open: false };

function fillTested(slug, t) {
  const card = $('tested-card');
  if (!card) return;
  lastTested = { slug, t };
  const label = { untested: 'Not tested', stale: 'Test out of date', failed: 'Failed', passed: 'Passed', skipped: 'Skipped' }[t.status] ?? t.status;
  const state = el('p', `note last ${t.unlocks ? 'passed' : 'failed'}`, `${label}: ${t.detail}`);
  state.setAttribute('role', 'status');
  const note = el('input');
  Object.assign(note, { id: 'test-note', type: 'text', maxLength: 300, placeholder: 'what you tried, or why you skip (optional)', autocomplete: 'off', spellcheck: false });
  const noteLabel = el('label', '', 'Note');
  noteLabel.htmlFor = 'test-note';
  const buttons = el('div', 'job-row');
  // While the emulator window is open the result is not in yet: the buttons wait for it to close.
  for (const [result, text, cls] of [['pass', 'Pass', 'apply'], ['fail', 'Fail', 'ghost'], ['skip', 'Skip', 'ghost']]) {
    const b = el('button', cls, text);
    b.type = 'button';
    b.disabled = emu.open;
    b.onclick = () => previewTest(slug, result, note.value);
    buttons.append(b);
  }
  buttons.style.gridTemplateColumns = 'repeat(4, max-content)';
  if (emu.active) {
    const stop = el('button', 'ghost', 'Stop watching');
    stop.type = 'button';
    stop.title = 'Studio stops watching the emulator and unlocks the buttons. The emulator stays open.';
    stop.onclick = async () => { await api('/api/emulator/stop', {}); pollEmulator(); };
    buttons.append(stop);
  }
  const windowText = emu.open ? 'The emulator is open: try the app, then close its window to record the result.'
    : emu.status === 'closed' ? 'The emulator was closed: record the result.' : '';
  const windowLine = el("p", "note", windowText);
  windowLine.setAttribute('role', 'status');
  card.replaceChildren(el('h2', 'label', 'Tested on device/emulator'),
    el('p', 'plan-note', 'Try the brand by hand (Build for test (DEV) above), then record the result for this commit. '
      + 'A release needs a Pass or a Skip; a new commit or a change to the brand resets it. Recording changes brands/'
      + `${slug}/studio.json: commit it.`),
    state, windowLine, noteLabel, note, buttons);
}

/// Asks Studio whether the emulator window is still open (it polls adb devices, read-only).
async function pollEmulator() {
  if (!['build', 'logs'].includes(state.view)) return;
  let now;
  try { now = (await api('/api/emulator')).data; } catch { return; }
  const changed = now.status !== emu.status;
  Object.assign(emu, now, { active: now.status === 'waiting' || now.status === 'watching' });
  if (changed && state.view === 'build' && lastTested?.slug === state.slug && $('tested-card')) fillTested(lastTested.slug, lastTested.t);
  // A logcat session shows the incidents it finds while it runs.
  if (state.view === 'logs' && run.jobs.some((j) => j.name === 'logcat' && j.state === 'running')) refreshJobs();
}
setInterval(pollEmulator, 3000);

async function previewTest(slug, result, note, acceptDirty) {
  const { data } = await api(`/api/brands/${encodeURIComponent(slug)}/tested/preview`, { result, note });
  $('side-jobs').hidden = true;
  $('side-plan').hidden = false;
  renderPlan(data, {
    title: `Test result · ${slug}`,
    applyLabel: `Record ${result}`,
    dirty: Array.isArray(acceptDirty) ? acceptDirty : undefined,
    onApply: (accept) => applyTest(slug, result, note, accept),
  });
}

async function applyTest(slug, result, note, acceptDirty) {
  const { status: code, data } = await api(`/api/brands/${encodeURIComponent(slug)}/tested/apply`, { result, note, acceptDirty });
  if (code === 409) return previewTest(slug, result, note, data.dirty);
  if (code !== 200) return planStatus(data.refused || data.error, true);
  await load(slug);
  $('side-plan').hidden = true;
  $('side-jobs').hidden = false;
  renderBuild();
  const s = $('build-status');
  if (s) s.textContent = `Recorded ${result} for ${slug}. Commit studio.json so the release counts it.`;
}

/// The release cards: what the server's release check says, then the job or the
/// Mac's prompt. Neither uploads anything: the stores stay a human's step.
async function fillRelease(slug) {
  const { data } = await api(`/api/brands/${encodeURIComponent(slug)}/release`);
  const card = $('release-card');
  if (!card || state.slug !== slug) return;
  const refused = data.refusal ?? [];
  fillTested(slug, data.tested);
  const head = el('p', 'plan-note', `pubspec ${data.version}: an AAB and an APK, signed with ${slug}'s upload key, checked `
    + '(package, version, target SDK, certificate, only this brand\'s assets, icon sizes), then copied to '
    + `dist/${slug}/${data.version}/ with release.json. About 20 minutes cold. Never uploads.`
    + (data.legacy ? ' A legacy brand: its backend items never block.' : ''));
  card.replaceChildren(el('h2', 'label', 'Release (Android)'), head);
  if (refused.length) {
    card.append(el('p', 'note', 'Refused, until:'));
    const ul = el('ul', 'refusal');
    for (const r of refused) ul.append(el('li', '', r));
    card.append(ul);
  }
  const row = el('div', 'job-row');
  const go = el('button', 'apply', 'Build release');
  go.type = 'button';
  go.disabled = refused.length > 0;
  go.onclick = () => startJob('release-android', slug);
  const last = run.jobs.find((j) => j.name === 'release-android' && j.slug === slug);
  row.append(go, ...(last ? [el('p', `note last ${last.state}`, `Last: ${last.state}${last.ms ? `, ${seconds(last.ms)}` : ''}`)] : []));
  card.append(row);
  card.append(el('p', 'note', `Test state: ${data.tested.status}${data.tested.unlocks ? '' : '. Record a result in "Tested on device/emulator" above'}.`));
  const done = data.history?.[0];
  if (done) {
    card.append(el('p', 'note', `Last release: ${done.versionName} (${done.versionCode}), commit ${done.commit}, ${done.builtAt}, `
      + `under dist/${slug}/. Uploaded by a human, not Studio.`));
  }

  // iOS: Studio cannot build it on Windows; it writes the Mac's instructions.
  const ios = $('ios-card');
  const field = (id, text, placeholder, mode) => {
    const label = el('label', '', text);
    label.htmlFor = id;
    const input = el('input');
    Object.assign(input, { id, type: 'text', placeholder, autocomplete: 'off', spellcheck: false, inputMode: mode });
    return [label, input];
  };
  // "e.g.": a placeholder that looks like a value reads as one already typed.
  const [vl, version] = field('ios-version', 'iOS version', 'e.g. 2.0.1', 'decimal');
  const [bl, build] = field('ios-build', 'Build number', 'e.g. 21', 'numeric');
  const out = el('div');
  const make = el('button', 'apply', 'Copy prompt for the Mac');
  make.type = 'button';
  // Said next to the button, not at the foot of the page where it scrolls out of sight.
  const said = el('p', 'note');
  said.setAttribute('role', 'status');
  const say = (t, err = false) => { said.textContent = t; said.style.color = err ? 'var(--err)' : ''; };
  const blocking = refused.filter((r) => !r.startsWith('release-without-brand-key'));
  make.disabled = blocking.length > 0;
  if (blocking.length) say(`Locked: ${blocking.join('; ')}`, true);
  make.onclick = async () => {
    const { status: code, data: d } = await api(`/api/brands/${encodeURIComponent(slug)}/macprompt`,
      { iosVersion: version.value.trim(), build: build.value.trim() });
    if (code !== 200) { say(d.error ?? 'Could not write the prompt', true); return; }
    const text = el('textarea', 'bundle');
    text.readOnly = true;
    text.value = d.text;
    text.setAttribute('aria-label', 'The prompt for Claude Code on the Mac, exactly what will be copied');
    out.replaceChildren(text);
    try {
      await navigator.clipboard.writeText(d.text);
      say('Copied: paste it into Claude Code on the Mac. It stops before Submit for Review.');
    } catch {
      say('Copy failed: select the text and copy it.', true);
    }
  };
  ios.replaceChildren(el('h2', 'label', 'iOS on the Mac'),
    el('p', 'plan-note', 'The App Store versions run ahead of Android\'s, so give the iOS version and a build number above the last one. '
      + 'The prompt names this commit, the build and export commands, and stops before "Submit for Review".'),
    vl, version, bl, build, make, said, out);
}

// ---- the side panel: jobs, the open one's incidents, its Fix Bundle ---------

function renderJobsSide() {
  const side = $('side-jobs');
  if (side.hidden) return;
  const list = el('ol', 'jobs');
  for (const j of run.jobs.slice(0, 20)) {
    const b = el('button', `job ${j.state}`);
    b.type = 'button';
    if (j.id === run.open) b.setAttribute('aria-current', 'true');
    b.append(el('span', 'st', j.state), el('span', 'k', run.names[j.name] ?? j.name),
      el('span', 'v', `${j.slug}${j.ms ? ` · ${seconds(j.ms)}` : ''}`));
    b.onclick = () => { follow(j.id); showView('logs'); };
    const li = el('li');
    li.append(b);
    list.append(li);
  }
  const parts = [el('h2', 'label', 'Jobs'), run.jobs.length ? list : el('p', 'none', 'None this session.'), ...proposalCards()];
  const job = openJob();
  if (job) parts.push(...jobDetail(job));
  parts.push(el('h2', 'label', 'Earlier logs'));
  const earlier = el('ol', 'jobs');
  for (const l of run.earlier.slice(0, 12)) {
    const b = el('button', 'job earlier');
    b.type = 'button';
    if (run.open === `log:${l.name}`) b.setAttribute('aria-current', 'true');
    b.append(el('span', 'k', l.name.replace(/\.log$/, '')), el('span', 'v', kb(l.bytes)));
    b.onclick = () => { showView('logs'); openEarlier(l.name); };
    const li = el('li');
    li.append(b);
    earlier.append(li);
  }
  parts.push(run.earlier.length ? earlier : el('p', 'none', 'None on disk.'));
  side.replaceChildren(...parts);
}

/// Solve, in order: the autofix, the nearest earlier cases, the Fix Bundle. It only
/// shows; the autofix is a button, and nothing is stored without a previewed Apply.
function solvePanel(job) {
  const out = [];
  const go = el('button', 'apply', run.solve?.id === job.id ? 'Solve again' : 'Solve');
  go.type = 'button';
  go.onclick = async () => {
    const { status: code, data } = await api(`/api/jobs/${encodeURIComponent(job.id)}/solve`, {});
    if (code !== 200) { announce(data.error ?? 'Could not solve', true); return; }
    run.solve = { id: job.id, stages: data.stages };
    run.bundle = null; // the bundle now lists what Solve showed
    renderJobsSide();
  };
  out.push(go);
  if (run.solve?.id !== job.id) {
    out.push(el('p', 'note', 'Solve goes in order: the fix for a known incident, the nearest earlier cases, then the Fix Bundle for Claude. Nothing runs until you press it.'));
    return out;
  }
  const list = el('ol', 'solve');
  let n = 0;
  for (const stage of run.solve.stages) {
    const li = el('li');
    n += 1;
    if (stage.stage === 'autofix') {
      li.append(el('strong', '', `${n}. Known fix`));
      const b = el('button', 'ghost get', stage.label);
      b.type = 'button';
      b.onclick = () => startJob(stage.job, job.slug, job.id);
      li.append(el('p', 'note', `Incident ${stage.incident}. It runs only when you press it.`), b);
    } else if (stage.stage === 'cases') {
      li.append(el('strong', '', `${n}. Nearest earlier cases`));
      if (!stage.cases.length) li.append(el('p', 'none', 'None yet: a case is saved when a fix works.'));
      for (const c of stage.cases) {
        const d = el('details', 'case');
        d.append(el('summary', '', `${c.id} · ${c.why}`), el('p', 'line', c.symptom), c.cause ? el('p', '', c.cause) : el('p', 'none', 'No cause recorded.'),
          el('p', 'meta', `${c.solvedBy} · ${c.date}`));
        if (c.diff) { const pre = el('pre', 'diff'); pre.textContent = c.diff; d.append(pre); }
        li.append(d);
      }
    } else {
      li.append(el('strong', '', `${n}. Fix Bundle`));
      li.append(el('p', 'note', 'Below. It lists the fix and the cases above as already tried, so Claude does not suggest them again.'));
    }
    list.append(li);
  }
  out.push(list);
  return out;
}

/// A case stored only when you apply it: the proposals Studio makes once a fix has worked.
function proposalCards() {
  const out = [];
  for (const p of run.proposals ?? []) {
    const card = el('div', 'incident');
    card.append(el('h3', '', 'A fix worked: save it as a case?'), el('p', 'line', p.symptom), el('p', '', `${p.solvedBy} · ${p.tests.join(', ')}`));
    const b = el('button', 'ghost get', 'Preview the case');
    b.type = 'button';
    b.onclick = () => previewCases('save', { proposal: p.id }, `Case · ${p.id}`, 'Save the case');
    card.append(b);
    out.push(card);
  }
  return out;
}

/// A previewed Apply for the case store, in the side panel (as the test record does).
async function previewCases(action, body, title, applyLabel, acceptDirty) {
  const { data } = await api(`/api/cases/${action}/preview`, body);
  $('side-jobs').hidden = true;
  $('side-plan').hidden = false;
  renderPlan(data, {
    title,
    applyLabel,
    dirty: Array.isArray(acceptDirty) ? acceptDirty : undefined,
    onApply: async (accept) => {
      const { status: code, data: d } = await api(`/api/cases/${action}/apply`, { ...body, acceptDirty: accept });
      if (code === 409) return previewCases(action, body, title, applyLabel, d.dirty);
      if (code !== 200) return planStatus(d.refused || d.error, true);
      $('side-plan').hidden = true;
      $('side-jobs').hidden = false;
      await refreshJobs();
      renderBuildCases?.();
      announce(`Stored ${d.written.length / 2} case${d.written.length === 2 ? '' : 's'}. Commit tool/studio/cases/ to share them.`);
    },
  });
}

function jobDetail(job) {
  const out = [el('h2', 'label', 'This job')];
  const cmds = el('ul', 'cmds');
  for (const c of job.commands) cmds.append(el('li', '', c));
  out.push(cmds);
  if (job.state === 'running' || job.state === 'queued') {
    const stop = el('button', 'ghost', job.state === 'queued' ? 'Remove from queue' : 'Cancel');
    stop.type = 'button';
    stop.onclick = async () => { await api(`/api/jobs/${encodeURIComponent(job.id)}/cancel`, {}); refreshJobs(); };
    out.push(stop);
  }
  if (job.state === 'failed') out.push(...solvePanel(job));
  if (job.state === 'failed' || job.name === 'logcat') {
    out.push(el('h2', 'label', 'Known incidents'));
    if (!job.matched.length) out.push(el('p', 'none', 'None matched: this may be a new incident. The Fix Bundle carries the log to Claude.'));
    for (const m of job.matched) {
      const card = el('div', 'incident');
      card.append(el('h3', '', m.title), el('p', 'line', m.line), el('p', '', m.cause), el('p', 'fix', m.fix));
      if (m.autofix) {
        const fix = el('button', 'ghost get', m.autofix.label);
        fix.type = 'button';
        fix.onclick = () => startJob(m.autofix.job, job.slug, job.id);
        card.append(fix);
      }
      card.append(el('p', 'meta', `${m.id} · ${m.evidence}`));
      out.push(card);
    }
  }
  if (job.state !== 'running' && job.state !== 'queued') {
    out.push(el('h2', 'label', 'Fix Bundle'));
    if (run.bundle?.id === job.id) {
      const text = el('textarea', 'bundle');
      text.readOnly = true;
      text.value = run.bundle.text;
      text.setAttribute('aria-label', 'Fix Bundle, exactly what will be copied');
      const copy = el('button', 'apply', 'Copy for Claude');
      copy.type = 'button';
      copy.onclick = async () => {
        await navigator.clipboard.writeText(run.bundle.text);
        copy.textContent = 'Copied';
        announce('Fix Bundle copied: paste it to Claude.');
      };
      out.push(el('p', 'note', `${run.bundle.text.length} of 8,000 characters, redacted. Read it before you copy it.`), text, copy);
    } else {
      const show = el('button', 'ghost', 'Show the Fix Bundle');
      show.type = 'button';
      show.onclick = async () => {
        const { data } = await api(`/api/jobs/${encodeURIComponent(job.id)}/bundle`);
        run.bundle = { id: job.id, text: data.text };
        renderJobsSide();
        document.querySelector('#side-jobs textarea.bundle')?.focus();
      };
      out.push(show);
    }
  }
  return out;
}

async function refreshEarlier() {
  run.earlier = (await api('/api/logs')).data;
  renderJobsSide();
}
