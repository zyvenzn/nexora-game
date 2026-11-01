import { auth, rpc } from '../api.js';
import { setMe } from '../state.js';
import { el, toast, friendly, setTitle, emblem } from '../ui.js';

async function loadMe() { const me = await rpc('get_me'); setMe(me); return me; }

function field(label, input, hint) {
  return el('label', { class: 'field' }, el('span', { class: 'field__label' }, label), input, hint ? el('span', { class: 'field__hint' }, hint) : null);
}

function form(onSubmit, ...kids) {
  const err = el('p', { class: 'form__error', role: 'alert' });
  const f = el('form', { class: 'form', novalidate: '' }, ...kids, err);
  const btn = f.querySelector('button[type=submit]');
  f.addEventListener('submit', async e => {
    e.preventDefault(); err.textContent = '';
    btn.disabled = true; const label = btn.textContent; btn.textContent = 'One moment';
    try { await onSubmit(f); } catch (ex) { err.textContent = friendly(ex); }
    btn.disabled = false; btn.textContent = label;
  });
  return f;
}

export async function render(ctx) {
  setTitle('Log in');
  if (auth.signedIn) {
    const me = await loadMe();
    location.hash = me.profile ? '#/packs' : '#/welcome';
    return el('div');
  }
  const mode = ctx.params.get('mode') === 'login' ? 'login' : 'signup';
  const box = el('div', { class: 'authbox' });
  const tabs = el('div', { class: 'seg', role: 'tablist' },
    el('a', { class: 'seg__item' + (mode === 'signup' ? ' is-on' : ''), href: '#/auth?mode=signup', role: 'tab', 'aria-selected': String(mode === 'signup') }, 'Create account'),
    el('a', { class: 'seg__item' + (mode === 'login' ? ' is-on' : ''), href: '#/auth?mode=login', role: 'tab', 'aria-selected': String(mode === 'login') }, 'Log in'));

  let f;
  if (mode === 'signup') {
    const u = el('input', { type: 'text', name: 'username', autocomplete: 'username', maxlength: '20', autocapitalize: 'none', spellcheck: 'false', required: '' });
    const em = el('input', { type: 'email', name: 'email', autocomplete: 'email', required: '' });
    const pw = el('input', { type: 'password', name: 'password', autocomplete: 'new-password', minlength: '8', required: '' });
    f = form(async () => {
      const username = u.value.trim().toLowerCase();
      if (!/^[a-z0-9_]{3,20}$/.test(username)) throw { message: 'bad_username' };
      if (pw.value.length < 8) throw { message: 'weak_password' };
      if (!(await rpc('username_available', { p_username: username }))) throw { message: 'username_taken' };
      await auth.signUp(em.value.trim(), pw.value);
      try { await rpc('create_profile', { p_username: username, p_display: username }); }
      catch (e) { if (e.message !== 'profile_exists') { await loadMe(); location.hash = '#/welcome'; toast(friendly(e), 'error'); return; } }
      await loadMe();
      toast('Welcome! Your free Starter Pack is waiting.', 'good');
      location.hash = '#/packs';
    },
      field('Username', u, '3 to 20 letters, numbers or underscores. Other players see this.'),
      field('Email', em, 'Only used to log in.'),
      field('Password', pw, 'At least 8 characters.'),
      el('button', { class: 'btn btn--wide', type: 'submit' }, 'Create account'));
  } else {
    const em = el('input', { type: 'email', name: 'email', autocomplete: 'email', required: '' });
    const pw = el('input', { type: 'password', name: 'password', autocomplete: 'current-password', required: '' });
    f = form(async () => {
      await auth.signIn(em.value.trim(), pw.value);
      const me = await loadMe();
      location.hash = me.profile ? '#/packs' : '#/welcome';
    }, field('Email', em), field('Password', pw), el('button', { class: 'btn btn--wide', type: 'submit' }, 'Log in'));
  }

  box.append(
    el('div', { class: 'authbox__head' }, emblem('moon', '#d8cbff', '#fff'), el('h1', { class: 'page-title' }, mode === 'signup' ? 'Join Nexora' : 'Welcome back')),
    mode === 'signup' ? el('p', { class: 'muted' }, 'Free account. You get 500 Stardust and a Starter Pack. Everything here is play money: nothing can be bought or cashed out.') : null,
    tabs, f);
  return box;
}

// Shown when someone signed up but has no username yet.
export async function renderWelcome() {
  setTitle('Pick a username');
  if (!auth.signedIn) { location.hash = '#/auth'; return el('div'); }
  const me = await loadMe();
  if (me.profile) { location.hash = '#/packs'; return el('div'); }
  const u = el('input', { type: 'text', name: 'username', autocomplete: 'username', maxlength: '20', autocapitalize: 'none', spellcheck: 'false', required: '' });
  const f = form(async () => {
    const username = u.value.trim().toLowerCase();
    if (!/^[a-z0-9_]{3,20}$/.test(username)) throw { message: 'bad_username' };
    await rpc('create_profile', { p_username: username, p_display: username });
    await loadMe();
    toast('Welcome! Your free Starter Pack is waiting.', 'good');
    location.hash = '#/packs';
  }, field('Username', u, '3 to 20 letters, numbers or underscores.'), el('button', { class: 'btn btn--wide', type: 'submit' }, 'Finish'));
  return el('div', { class: 'authbox' }, el('h1', { class: 'page-title' }, 'Pick a username'), el('p', { class: 'muted' }, 'This is how other players will find you.'), f);
}
