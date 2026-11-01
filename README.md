# Nexora (play-money card game)

Open packs, tear them, flip cards, collect, climb the leaderboard. Stardust is play money only.

## Folder
- `site/`   the website (static, no build). Deploy this folder.
- `setup.sql`   the whole database. Run once in Supabase.
- `sql/07_card_expansion.sql`   additive catalog update for existing projects.

## Setup (all from a phone browser)
1. supabase.com > New project. Wait until it is ready.
2. Authentication > Providers > Email: turn OFF "Confirm email" (otherwise sign-ups wait for a mail).
3. SQL Editor > New query. Paste all of `setup.sql` > Run. It should end without errors.
4. Project Settings > API. Copy "Project URL" and the "anon public" key.
5. Open `site/config.js`, paste both values between the quotes. Never use the service_role key.
6. Deploy: Vercel > Add New Project > import your GitHub repo > Root Directory `site` (or put `site/` contents at repo root) > Deploy.
7. Open the site, create your account.
8. Make yourself admin: SQL Editor, run
   `update profiles set role='admin' where username='YOURNAME';`

## Card expansion
- The catalog has five rarity tiers and four elements.
- For an existing database, run `sql/07_card_expansion.sql` once in Supabase SQL Editor. It adds 20 premium SVG card artworks without resetting player collections or serials.
- Card tiles show a NEXORA watermark, element, rarity and Stardust reference value.
- Pack-opening SFX are synthesized in-browser; the sound toggle is saved locally.

## Notes
- Players cannot read or write tables directly. All game rules run in database functions.
- Card art is AI-generated and the footer says so.
- Add cards later: admin functions `admin_upsert_card` / `admin_upsert_pack` (admin panel UI comes in phase 2). Put new PNGs in `site/assets/cards/`.
- Still to come (backend is done and tested, UI is not): marketplace, auctions, trades, crafting, admin panel.
