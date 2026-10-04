// SPC Studio, New brand: one form, one previewed Apply. It creates the brand
// folder (brand.json, studio.json, the logo), the Android res/, the iOS
// xcconfig and asset catalog, the flavor entry point and the pubspec block.
'use strict';

const LANGUAGES = { en: 'English', fr: 'Français', ar: 'العربية', es: 'Español', sl: 'Slovenščina', de: 'Deutsch', sq: 'Shqip' };
const wizard = {
  form: { slug: '', name: '', applicationId: '', apiBaseUrl: '', locales: ['en'],
    colors: { primary: '#1d4ed8', accent: '#dbeafe', surface: '#f8fafc', cta: '#f59e0b', ctaText: '#111827' },
    companyName: '', country: '', supportEmail: '', termsUrl: '', privacyUrl: '' },
  idEdited: false,
  logo: null, // base64
  logoName: '',
  seq: 0,
};
let wizardTimer = null;

// Problems name brand.json paths; these have no input of their own.
const ALIAS = { 'mobile.displayName': 'name', 'mobile.bundleIdentifier': 'mobile.applicationId',
  'mobile.deepLinkScheme': 'slug', defaultLocale: 'locales' };

function renderWizard() {
  const f = wizard.form;
  const view = $('view-wizard');
  const head = el('div', 'sheet-head');
  head.append(el('h1', '', 'New brand'));

  const text = (path, key, label, hint, placeholder = '') => {
    const row = el('div', 'field');
    row.dataset.path = path;
    const id = `w-${key}`;
    const l = el('label', 'key', label);
    l.htmlFor = id;
    const control = el('div', 'control');
    const i = el('input');
    i.type = 'text';
    i.id = id;
    i.value = f[key];
    i.placeholder = placeholder;
    i.oninput = () => {
      f[key] = i.value;
      if (key === 'slug' && !wizard.idEdited) {
        f.applicationId = i.value ? `com.transasim.${i.value}` : '';
        $('w-applicationId').value = f.applicationId;
      }
      if (key === 'applicationId') wizard.idEdited = true;
      scheduleWizard();
    };
    control.append(i);
    row.append(l, control);
    if (hint) row.append(el('div', 'msg hint', hint));
    return row;
  };
  const group = (title, kids) => {
    const d = el('details');
    d.open = true;
    const g = el('div', 'group');
    g.append(...kids);
    d.append(el('summary', '', title), g);
    return d;
  };

  const colours = Object.keys(f.colors).map((role) => {
    const row = el('div', 'field');
    row.dataset.path = `colors.${role}`;
    const l = el('label', 'key', role);
    l.htmlFor = `w-colour-${role}`;
    const control = el('div', 'control');
    const t = el('input');
    t.type = 'text';
    t.id = `w-colour-${role}`;
    t.value = f.colors[role];
    const pick = el('input');
    pick.type = 'color';
    pick.value = f.colors[role];
    pick.setAttribute('aria-label', `${role} colour`);
    t.oninput = () => { f.colors[role] = t.value; if (/^#[0-9a-f]{6}$/i.test(t.value)) pick.value = t.value.toLowerCase(); scheduleWizard(); };
    pick.oninput = () => { f.colors[role] = pick.value; t.value = pick.value; scheduleWizard(); };
    control.append(t, pick);
    row.append(l, control);
    return row;
  });

  const locales = el('div', 'field');
  locales.dataset.path = 'locales';
  const lc = el('div', 'control locales');
  for (const [code, name] of Object.entries(LANGUAGES)) {
    const lab = el('label', 'check');
    const c = el('input');
    c.type = 'checkbox';
    c.checked = f.locales.includes(code);
    c.onchange = () => {
      f.locales = Object.keys(LANGUAGES).filter((k) => k === code ? c.checked : f.locales.includes(k));
      scheduleWizard();
    };
    lab.append(c, document.createTextNode(` ${name}`));
    lc.append(lab);
  }
  locales.append(el('span', 'key', 'locales'), lc, el('div', 'msg hint', 'The first ticked is the default language.'));

  const logo = el('div', 'field');
  logo.dataset.path = 'logo.mark';
  const logoControl = el('div', 'control');
  logoControl.append(dropZone(wizard.logo ? `${wizard.logoName}: drop another to replace` : 'Drop the logo mark (square PNG)', 'image/png,image/jpeg', async (file) => {
    wizard.logo = await fileToBase64(file);
    wizard.logoName = file.name;
    renderWizard();
    scheduleWizard();
  }));
  logo.append(el('span', 'key', 'logo mark'), logoControl);

  const form = el('form', 'form');
  form.autocomplete = 'off';
  form.spellcheck = false;
  form.onsubmit = (e) => e.preventDefault();
  form.append(
    group('Identity', [
      text('slug', 'slug', 'slug', 'The folder name and flavor: lowercase letters and digits.', 'demo'),
      text('name', 'name', 'display name', 'Under the icon and in the stores.', 'Demo eSIM'),
      text('mobile.applicationId', 'applicationId', 'applicationId', 'Also the iOS bundle id. FROZEN once published: a new id is a new store listing, and every install is orphaned.', 'com.transasim.demo'),
      text('mobile.apiBaseUrl', 'apiBaseUrl', 'backend URL', 'This brand’s own backend; no two brands share one.', 'https://demo.transasim.com/api'),
    ]),
    group('Colours', colours),
    group('Languages and logo', [locales, logo]),
    group('Required by BrandConfig', [
      text('legal.companyName', 'companyName', 'company name', 'The legal entity behind the brand.'),
      text('legal.country', 'country', 'country', 'ISO 3166 two letters, e.g. BE. No default, on purpose.', 'BE'),
      text('support.email', 'supportEmail', 'support email', '', 'support@example.com'),
      text('legal.termsUrl', 'termsUrl', 'terms URL', 'https, and a page with content.', 'https://'),
      text('legal.privacyUrl', 'privacyUrl', 'privacy URL', 'https, and a page with content.', 'https://'),
    ]),
  );
  view.replaceChildren(head, form);
  scheduleWizard();
}

function scheduleWizard() {
  clearTimeout(wizardTimer);
  wizardTimer = setTimeout(previewWizard, 350);
}

async function previewWizard(acceptDirty) {
  if (state.view !== 'wizard') return;
  const seq = ++wizard.seq;
  const { data } = await api('/api/new/preview', { form: wizard.form, logo: wizard.logo });
  if (seq !== wizard.seq) return;
  markWizard(data);
  renderPlan(data, {
    title: `New brand${wizard.form.slug ? ` · ${wizard.form.slug}` : ''}`,
    applyLabel: `Create ${wizard.form.name || 'brand'}`,
    dirty: Array.isArray(acceptDirty) ? acceptDirty : undefined,
    onApply: createBrand,
  });
}

/// Errors and warnings next to the input they are about.
function markWizard(plan) {
  const view = $('view-wizard');
  view.querySelectorAll('.msg:not(.hint)').forEach((m) => m.remove());
  view.querySelectorAll('.field.err, .field.warn').forEach((m) => m.classList.remove('err', 'warn'));
  for (const [list, level] of [[plan.errors, 'err'], [plan.warnings, 'warn']]) {
    for (const p of list) {
      const path = ALIAS[p.field] ?? p.field;
      const row = view.querySelector(`.field[data-path="${CSS.escape(path)}"]`);
      if (!row || row.classList.contains('err')) continue;
      row.classList.add(level);
      row.append(el('div', 'msg', p.reason));
    }
  }
}

async function createBrand(acceptDirty) {
  const { status: code, data } = await api('/api/new/apply', { form: wizard.form, logo: wizard.logo, acceptDirty });
  if (code === 409) return previewWizard(data.dirty);
  if (code !== 200) return planStatus(data.refused || data.error, true);
  const slug = wizard.form.slug;
  wizard.logo = null;
  wizard.idEdited = false;
  wizard.form = { ...wizard.form, slug: '', name: '', applicationId: '', apiBaseUrl: '' };
  await reloadBrands(slug);
  status(`Created ${slug}: ${data.written.length} files. Run flutter test, then review and commit.`);
}
