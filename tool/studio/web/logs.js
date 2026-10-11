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
  renderJobsSide();
}

async function startJob(job, slug = 'studio') {
  const { status: code, data } = await api('/api/jobs', { job, slug });
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
  view.replaceChildren(head, counts, said, run.open ? box : el('p', 'none', 'No job yet. Start one from Build or Doctor.'));
  renderLogHead();
  renderLines();
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
  const phase2 = state.studio[slug]?.backend?.phase2;
  dev.append(el('h2', 'label', 'Test on DEV'),
    el('p', 'plan-note', phase2
      ? `A profile APK with API_BASE_URL set to the DEV backend${state.studio[slug].backend.features?.payments ? ' and its pk_test_ key' : ''}. Never a release.`
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
  const said = el('p', 'toast');
  said.id = 'build-status';
  said.setAttribute('role', 'status');
  $('view-build').replaceChildren(head, card, dev, said);
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
  const parts = [el('h2', 'label', 'Jobs'), run.jobs.length ? list : el('p', 'none', 'None this session.')];
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
  if (job.state === 'failed') {
    out.push(el('h2', 'label', 'Known incidents'));
    if (!job.matched.length) out.push(el('p', 'none', 'None matched: this may be a new incident. The Fix Bundle carries the log to Claude.'));
    for (const m of job.matched) {
      const card = el('div', 'incident');
      card.append(el('h3', '', m.title), el('p', 'line', m.line), el('p', '', m.cause), el('p', 'fix', m.fix));
      if (m.autofix) {
        const fix = el('button', 'ghost get', m.autofix.label);
        fix.type = 'button';
        fix.onclick = () => startJob(m.autofix.job);
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
