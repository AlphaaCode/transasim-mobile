// SPC Studio: Doctor. What this machine has, read fresh each time the tab
// opens. A fix is a job the user starts from its button; nothing installs
// on its own, and no licence is ever accepted for anyone.
'use strict';

let doctorSeq = 0;

async function renderDoctor() {
  const seq = ++doctorSeq;
  const view = $('view-doctor');
  const head = el('div', 'sheet-head');
  const again = el('button', 'ghost', 'Check again');
  again.type = 'button';
  again.onclick = renderDoctor;
  head.append(el('h1', '', 'Doctor'), el('div', 'chips'), again);
  const said = el('p', 'toast');
  said.setAttribute('role', 'status');
  said.textContent = 'Checking this machine…';
  view.replaceChildren(head, said);

  const { data } = await api('/api/doctor');
  if (seq !== doctorSeq || state.view !== 'doctor') return;
  const checks = data.checks;
  const count = (s) => checks.filter((c) => c.status === s).length;
  head.querySelector('.chips').replaceChildren(
    el('span', `chip ${count('fail') ? 'err' : 'ok'}`, `${count('fail')} failing`),
    el('span', `chip ${count('warn') ? 'warn' : 'ok'}`, `${count('warn')} to look at`),
    el('span', 'chip ok', `${count('ok')} fine`),
  );
  said.textContent = count('fail')
    ? `${count('fail')} check${count('fail') > 1 ? 's' : ''} failing.`
    : 'Nothing failing.';
  const groups = [];
  for (const group of [...new Set(checks.map((c) => c.group))]) {
    const section = el('section', 'doctor-group');
    section.append(el('h2', 'label', group));
    const list = el('ul', 'checks');
    for (const c of checks.filter((x) => x.group === group)) {
      const li = el('li', `check-row ${c.status}`);
      li.append(el('span', 'st', c.status), el('span', 'k', c.label), el('span', 'v', c.detail));
      if (c.fix) {
        const fix = el('button', 'ghost get', c.fix.label);
        fix.type = 'button';
        fix.onclick = () => startJob(c.fix.job);
        li.append(fix);
      }
      list.append(li);
    }
    section.append(list);
    groups.push(section);
  }
  view.append(...groups);
}
