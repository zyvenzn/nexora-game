import { rpc, auth, uploadProfileImage } from '../api.js';
import { state, setMe, clearMe } from '../state.js';
import { el, avatar, toast, friendly, setTitle, prepareImage } from '../ui.js';

export async function render() {
  setTitle('Settings');
  const root = el('div', { class: 'page page--narrow' });

  function draw() {
    const p = state.profile;
    const bannerBox = el('div', { class: 'pf__banner pf__banner--edit' }, p.banner_url ? el('img', { src: p.banner_url, alt: 'Your banner' }) : null);
    const avatarBox = el('div', { class: 'avatar-edit' }, avatar(p, 88));

    function picker(label, kind, w, h, hint) {
      const input = el('input', { type: 'file', accept: 'image/png,image/jpeg,image/webp', class: 'sr-only' });
      const b = el('button', { class: 'btn btn--ghost btn--small', type: 'button' }, label);
      b.addEventListener('click', () => input.click());
      input.addEventListener('change', async () => {
        const file = input.files && input.files[0]; if (!file) return;
        b.disabled = true; const old = b.textContent; b.textContent = 'Uploading';
        try {
          const blob = await prepareImage(file, w, h);
          const url = await uploadProfileImage(blob, kind);
          setMe(await rpc('update_profile', kind === 'avatar' ? { p_avatar: url } : { p_banner: url }));
          toast(kind === 'avatar' ? 'Profile picture updated.' : 'Banner updated.', 'good');
          draw();
        } catch (e) {
          toast(e && /^bad_image_(type|size)$/.test(e.message) ? 'Use a PNG, JPG or WebP image under 12 MB.' : friendly(e), 'error');
          b.disabled = false; b.textContent = old;
        }
      });
      const remove = el('button', { class: 'linkbtn', type: 'button' }, 'Remove');
      remove.addEventListener('click', async () => {
        try { setMe(await rpc('update_profile', kind === 'avatar' ? { p_avatar: '' } : { p_banner: '' })); draw(); } catch (e) { toast(friendly(e), 'error'); }
      });
      return el('div', { class: 'picker' }, b, (kind === 'avatar' ? p.avatar_url : p.banner_url) ? remove : null, input, el('span', { class: 'muted small' }, hint));
    }

    // display name + bio
    const dn = el('input', { type: 'text', value: p.display_name, maxlength: '30', required: '' });
    const bio = el('textarea', { rows: '3', maxlength: '160' }); bio.value = p.bio || '';
    const count = el('span', { class: 'muted small' }, `${bio.value.length} / 160`);
    bio.addEventListener('input', () => { count.textContent = `${bio.value.length} / 160`; });
    const err1 = el('p', { class: 'form__error', role: 'alert' });
    const profileForm = el('form', { class: 'form', novalidate: '' },
      el('label', { class: 'field' }, el('span', { class: 'field__label' }, 'Display name'), dn),
      el('label', { class: 'field' }, el('span', { class: 'field__label' }, 'Bio'), bio, count),
      err1, el('button', { class: 'btn', type: 'submit' }, 'Save profile'));
    profileForm.addEventListener('submit', async e => {
      e.preventDefault(); err1.textContent = '';
      try { setMe(await rpc('update_profile', { p_display: dn.value, p_bio: bio.value })); toast('Profile saved.', 'good'); draw(); }
      catch (ex) { err1.textContent = friendly(ex); }
    });

    // username
    const un = el('input', { type: 'text', value: p.username, maxlength: '20', autocapitalize: 'none', spellcheck: 'false' });
    const err2 = el('p', { class: 'form__error', role: 'alert' });
    const userForm = el('form', { class: 'form', novalidate: '' },
      el('label', { class: 'field' }, el('span', { class: 'field__label' }, 'Username'), un, el('span', { class: 'field__hint' }, 'You can change it once a week. Your profile link changes with it.')),
      err2, el('button', { class: 'btn btn--ghost', type: 'submit' }, 'Change username'));
    userForm.addEventListener('submit', async e => {
      e.preventDefault(); err2.textContent = '';
      if (un.value.trim().toLowerCase() === p.username) return;
      try { setMe(await rpc('change_username', { p_new: un.value })); toast('Username changed.', 'good'); draw(); }
      catch (ex) { err2.textContent = friendly(ex); }
    });

    const out = el('button', { class: 'btn btn--ghost', type: 'button' }, 'Log out');
    out.addEventListener('click', async () => { await auth.signOut(); clearMe(); toast('Logged out.'); location.hash = '#/'; });

    root.replaceChildren(
      el('div', { class: 'page__head' }, el('h1', { class: 'page-title' }, 'Settings'), el('a', { class: 'btn btn--ghost btn--small', href: '#/u/' + p.username }, 'View profile')),
      el('section', { class: 'panel' },
        el('h2', {}, 'Pictures'), bannerBox, picker('Change banner', 'banner', 1500, 500, 'Wide image, shown at the top of your profile.'),
        el('div', { class: 'avatar-row' }, avatarBox, picker('Change picture', 'avatar', 400, 400, 'Square, shown next to your name.'))),
      el('section', { class: 'panel' }, el('h2', {}, 'Profile'), profileForm),
      el('section', { class: 'panel' }, el('h2', {}, 'Username'), userForm),
      el('section', { class: 'panel' }, el('h2', {}, 'Account'), el('p', { class: 'muted' }, auth.user ? auth.user.email : ''), out));
  }
  draw();
  return root;
}
