-- =====================================================================
-- Part 2: helpers, accounts, packs, collection, crafting
-- Every function below runs with the owner's rights; tables are not
-- readable or writable by players directly (see 05_security.sql).
-- Error messages are short codes the website turns into sentences.
-- =====================================================================

-- ---------- helpers (not callable from the website) ----------
create or replace function public._cfg(k text) returns bigint
language sql stable set search_path = public, pg_temp as $$
  select (value #>> '{}')::bigint from public.settings where key = k
$$;

create or replace function public._uid() returns uuid
language plpgsql stable set search_path = public, pg_temp as $$
declare u uuid;
begin
  u := auth.uid();
  if u is null then raise exception 'not_signed_in'; end if;
  return u;
end $$;

create or replace function public._player() returns public.profiles
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = public._uid();
  if not found then raise exception 'no_profile'; end if;
  if p.banned then raise exception 'banned'; end if;
  return p;
end $$;

create or replace function public._admin() returns public.profiles
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare p public.profiles;
begin
  p := public._player();
  if p.role <> 'admin' then raise exception 'not_admin'; end if;
  return p;
end $$;

create or replace function public._lock_profiles(a uuid, b uuid) returns void
language sql security definer set search_path = public, pg_temp as $$
  select 1 from public.profiles where id in (a, b) order by id for update
$$;

create or replace function public._coins(p_uid uuid, p_delta bigint, p_reason text, p_ref text default null)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare nb bigint;
begin
  update public.profiles set balance = balance + p_delta
   where id = p_uid and balance + p_delta >= 0
   returning balance into nb;
  if not found then
    if exists (select 1 from public.profiles where id = p_uid) then
      raise exception 'insufficient_funds';
    end if;
    raise exception 'no_profile';
  end if;
  insert into public.ledger (user_id, delta, balance_after, reason, ref)
  values (p_uid, p_delta, nb, p_reason, p_ref);
  return nb;
end $$;

create or replace function public._mint(p_owner uuid, p_def text, p_via text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare sn int; iid uuid;
begin
  insert into public.card_serials (def_id, last_serial) values (p_def, 1)
  on conflict (def_id) do update set last_serial = public.card_serials.last_serial + 1
  returning last_serial into sn;
  insert into public.cards_owned (owner, def_id, serial, acquired_via)
  values (p_owner, p_def, sn, p_via) returning id into iid;
  return iid;
end $$;

create or replace function public._add_pack(p_uid uuid, p_pack text, p_qty int) returns void
language sql security definer set search_path = public, pg_temp as $$
  insert into public.pack_inventory (user_id, pack_type, qty) values (p_uid, p_pack, p_qty)
  on conflict (user_id, pack_type) do update set qty = public.pack_inventory.qty + excluded.qty
$$;

-- Reference value of a card: average of its last 5 sales, else its base price.
create or replace function public._value(p_def text) returns bigint
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(
    (select round(avg(price))::bigint from (select price from public.sales where def_id = p_def order by id desc limit 5) s),
    (select coalesce(d.base_price, r.base_price)::bigint from public.card_defs d join public.rarities r on r.id = d.rarity where d.id = p_def)
  )
$$;

create or replace function public._card_obj(p_instance uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'id', co.id, 'def_id', d.id, 'name', d.name, 'rarity', d.rarity, 'rank', r.rank,
    'element', d.element, 'image', d.image, 'blurb', d.blurb, 'serial', co.serial,
    'status', co.status, 'value', public._value(d.id))
  from public.cards_owned co
  join public.card_defs d on d.id = co.def_id
  join public.rarities r on r.id = d.rarity
  where co.id = p_instance
$$;

create or replace function public._pick_weighted(ids text[], w numeric[]) returns text
language plpgsql as $$
declare tot numeric := 0; r numeric; acc numeric := 0; i int;
begin
  for i in 1..coalesce(array_length(w, 1), 0) loop tot := tot + w[i]; end loop;
  if tot <= 0 then
    return ids[1 + floor(random() * array_length(ids, 1))::int];
  end if;
  r := random() * tot;
  for i in 1..array_length(ids, 1) loop
    acc := acc + w[i];
    if r < acc then return ids[i]; end if;
  end loop;
  return ids[array_length(ids, 1)];
end $$;

create or replace function public._user_json(p_uid uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('id', id, 'username', username, 'display_name', display_name, 'avatar_url', avatar_url)
  from public.profiles where id = p_uid
$$;

create or replace function public._audit(p_action text, p_target text, p_details jsonb default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.audit_log (admin_id, action, target, details) values (public._uid(), p_action, p_target, p_details);
end $$;

-- ---------- account ----------
create or replace function public.username_available(p_username text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select lower(trim(p_username)) ~ '^[a-z0-9_]{3,20}$'
     and lower(trim(p_username)) <> all (array['admin','administrator','nexora','support','system','moderator','mod','staff','official','root'])
     and not exists (select 1 from public.profiles where lower(username) = lower(trim(p_username)))
$$;

create or replace function public.create_profile(p_username text, p_display text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := public._uid(); u text := lower(trim(coalesce(p_username, ''))); dn text := nullif(trim(coalesce(p_display, '')), '');
begin
  if exists (select 1 from public.profiles where id = uid) then raise exception 'profile_exists'; end if;
  if u !~ '^[a-z0-9_]{3,20}$' then raise exception 'bad_username'; end if;
  if u = any (array['admin','administrator','nexora','support','system','moderator','mod','staff','official','root']) then
    raise exception 'username_reserved';
  end if;
  if exists (select 1 from public.profiles where lower(username) = u) then raise exception 'username_taken'; end if;
  dn := coalesce(left(dn, 30), u);
  insert into public.profiles (id, username, display_name) values (uid, u, dn);
  perform public._coins(uid, public._cfg('starting_balance'), 'welcome');
  perform public._add_pack(uid, 'starter', 1);
  return public.get_me();
exception when unique_violation then
  raise exception 'username_taken';
end $$;

create or replace function public.get_me() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = public._uid();
  if not found then return jsonb_build_object('signed_in', true, 'profile', null); end if;
  return jsonb_build_object(
    'signed_in', true,
    'profile', jsonb_build_object(
      'id', p.id, 'username', p.username, 'display_name', p.display_name, 'bio', p.bio,
      'avatar_url', p.avatar_url, 'banner_url', p.banner_url, 'balance', p.balance,
      'role', p.role, 'banned', p.banned, 'ban_reason', p.ban_reason, 'created_at', p.created_at,
      'next_daily_at', case when p.last_daily is null then null
                            else p.last_daily + make_interval(hours => public._cfg('daily_hours')::int) end),
    'packs', (select coalesce(jsonb_object_agg(pack_type, qty), '{}'::jsonb) from public.pack_inventory where user_id = p.id and qty > 0),
    'incoming_trades', (select count(*) from public.trades where to_user = p.id and status = 'pending' and expires_at > now()),
    'config', jsonb_build_object('fee_pct', public._cfg('market_fee_pct'), 'daily_bonus', public._cfg('daily_bonus'))
  );
end $$;

create or replace function public.update_profile(p_display text default null, p_bio text default null,
                                                 p_avatar text default null, p_banner text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); dn text; marker text;
begin
  marker := '/storage/v1/object/public/profiles/' || me.id::text || '/';
  if p_display is not null then
    dn := trim(p_display);
    if char_length(dn) < 1 or char_length(dn) > 30 or dn ~ '[\x00-\x1f]' then raise exception 'bad_display_name'; end if;
  end if;
  if p_bio is not null and (char_length(p_bio) > 160 or p_bio ~ '[\x00-\x08\x0b-\x1f]') then raise exception 'bad_bio'; end if;
  if p_avatar is not null and p_avatar <> '' and (p_avatar !~ '^https://' or position(marker in p_avatar) = 0) then raise exception 'bad_image_url'; end if;
  if p_banner is not null and p_banner <> '' and (p_banner !~ '^https://' or position(marker in p_banner) = 0) then raise exception 'bad_image_url'; end if;
  update public.profiles set
    display_name = coalesce(dn, display_name),
    bio          = coalesce(p_bio, bio),
    avatar_url   = case when p_avatar is null then avatar_url when p_avatar = '' then null else p_avatar end,
    banner_url   = case when p_banner is null then banner_url when p_banner = '' then null else p_banner end
  where id = me.id;
  return public.get_me();
end $$;

create or replace function public.change_username(p_new text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); u text := lower(trim(coalesce(p_new, '')));
begin
  if me.username_changed_at is not null
     and me.username_changed_at + make_interval(days => public._cfg('username_change_days')::int) > now() then
    raise exception 'username_cooldown';
  end if;
  if u !~ '^[a-z0-9_]{3,20}$' then raise exception 'bad_username'; end if;
  if u = any (array['admin','administrator','nexora','support','system','moderator','mod','staff','official','root']) then
    raise exception 'username_reserved';
  end if;
  if exists (select 1 from public.profiles where lower(username) = u and id <> me.id) then raise exception 'username_taken'; end if;
  update public.profiles set username = u, username_changed_at = now() where id = me.id;
  return public.get_me();
exception when unique_violation then
  raise exception 'username_taken';
end $$;

create or replace function public.claim_daily() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); bonus bigint := public._cfg('daily_bonus');
begin
  select * into me from public.profiles where id = me.id for update;
  if me.last_daily is not null and now() < me.last_daily + make_interval(hours => public._cfg('daily_hours')::int) then
    raise exception 'daily_not_ready';
  end if;
  update public.profiles set last_daily = now() where id = me.id;
  perform public._coins(me.id, bonus, 'daily');
  return public.get_me();
end $$;

-- ---------- catalog and feed (public) ----------
create or replace function public.get_catalog() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'rarities', (select coalesce(jsonb_agg(to_jsonb(r) order by r.rank), '[]'::jsonb) from public.rarities r),
    'cards', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', d.id, 'name', d.name, 'rarity', d.rarity, 'element', d.element, 'image', d.image,
        'blurb', d.blurb, 'value', public._value(d.id),
        'floor', (select min(l.price) from public.listings l join public.cards_owned c on c.id = l.instance_id where l.status = 'active' and c.def_id = d.id),
        'last_sale', (select s.price from public.sales s where s.def_id = d.id order by s.id desc limit 1),
        'minted', coalesce((select last_serial from public.card_serials cs where cs.def_id = d.id), 0),
        'holders', (select count(distinct owner) from public.cards_owned c where c.def_id = d.id and c.status <> 'burned')
      ) order by r.rank, d.id), '[]'::jsonb)
      from public.card_defs d join public.rarities r on r.id = d.rarity where d.active),
    'packs', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'description', description, 'element', element, 'price', price,
        'cards_count', cards_count, 'odds', odds, 'guarantee_rarity', guarantee_rarity, 'purchasable', purchasable
      ) order by sort), '[]'::jsonb) from public.pack_types where active),
    'recipes', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from public.craft_recipes c where active),
    'config', jsonb_build_object('fee_pct', public._cfg('market_fee_pct'), 'daily_bonus', public._cfg('daily_bonus'),
                                 'daily_hours', public._cfg('daily_hours'), 'trade_expiry_hours', public._cfg('trade_expiry_hours'))
  )
$$;

create or replace function public.feed_recent(p_limit int default 12) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('kind', f.kind, 'at', f.at, 'payload', f.payload,
           'user', public._user_json(f.user_id)) order by f.id desc), '[]'::jsonb)
  from (select * from public.feed order by id desc limit least(greatest(p_limit, 1), 50)) f
$$;

-- ---------- packs ----------
create or replace function public.buy_pack(p_pack text, p_qty int default 1) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); pt public.pack_types;
begin
  if p_qty is null or p_qty < 1 or p_qty > 20 then raise exception 'bad_quantity'; end if;
  select * into pt from public.pack_types where id = p_pack and active and purchasable;
  if not found then raise exception 'unknown_pack'; end if;
  perform public._coins(me.id, -(pt.price::bigint * p_qty), 'buy_pack', pt.id);
  perform public._add_pack(me.id, pt.id, p_qty);
  return public.get_me();
end $$;

create or replace function public.open_pack(p_pack text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  me public.profiles := public._player();
  pt public.pack_types;
  g_rank int; is_last boolean;
  rids text[]; rw numeric[]; cids text[]; cw numeric[];
  chosen_r text; chosen_d text; iid uuid;
  owned_defs text[]; out jsonb := '[]'::jsonb; obj jsonb; is_new boolean; rk int;
  i int;
begin
  select * into pt from public.pack_types where id = p_pack and active;
  if not found then raise exception 'unknown_pack'; end if;
  update public.pack_inventory set qty = qty - 1
   where user_id = me.id and pack_type = pt.id and qty > 0;
  if not found then raise exception 'no_pack'; end if;

  if pt.guarantee_rarity is not null then
    select rank into g_rank from public.rarities where id = pt.guarantee_rarity;
  end if;
  select coalesce(array_agg(distinct def_id), '{}') into owned_defs
    from public.cards_owned where owner = me.id and status <> 'burned';

  for i in 1..pt.cards_count loop
    is_last := (i = pt.cards_count);
    select array_agg(r.id order by r.rank), array_agg(coalesce((pt.odds ->> r.id)::numeric, 0) order by r.rank)
      into rids, rw
      from public.rarities r
     where exists (select 1 from public.card_defs d where d.rarity = r.id and d.active)
       and (not is_last or g_rank is null or r.rank >= g_rank);
    if rids is null then
      select array_agg(r.id order by r.rank), array_agg(coalesce((pt.odds ->> r.id)::numeric, 0) order by r.rank)
        into rids, rw
        from public.rarities r
       where exists (select 1 from public.card_defs d where d.rarity = r.id and d.active);
    end if;
    if rids is null then raise exception 'no_cards'; end if;
    chosen_r := public._pick_weighted(rids, rw);
    select array_agg(d.id order by d.id),
           array_agg((case when d.element = pt.element then pt.element_bias else 1 end)::numeric order by d.id)
      into cids, cw
      from public.card_defs d where d.rarity = chosen_r and d.active;
    chosen_d := public._pick_weighted(cids, cw);
    iid := public._mint(me.id, chosen_d, 'pack');
    is_new := not (chosen_d = any (owned_defs));
    owned_defs := owned_defs || chosen_d;
    obj := public._card_obj(iid) || jsonb_build_object('is_new', is_new);
    out := out || jsonb_build_array(obj);
    rk := (obj ->> 'rank')::int;
    if rk >= 1 then
      insert into public.feed (kind, user_id, payload)
      values ('pull', me.id, jsonb_build_object('name', obj ->> 'name', 'rarity', obj ->> 'rarity', 'def_id', chosen_d, 'serial', (obj ->> 'serial')::int, 'pack', pt.id));
    end if;
  end loop;

  insert into public.pack_openings (user_id, pack_type, cards) values (me.id, pt.id, out);
  return jsonb_build_object('pack', pt.id, 'cards', out, 'me', public.get_me());
end $$;

-- ---------- collection ----------
create or replace function public.my_collection() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player();
begin
  return jsonb_build_object(
    'cards', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'def_id', def_id, 'serial', serial, 'status', status,
                'via', acquired_via, 'at', acquired_at) order by acquired_at desc, serial), '[]'::jsonb)
              from public.cards_owned where owner = me.id and status <> 'burned'),
    'packs', (select coalesce(jsonb_object_agg(pack_type, qty), '{}'::jsonb) from public.pack_inventory where user_id = me.id and qty > 0));
end $$;

create or replace function public.craft_pack(p_recipe text, p_ids uuid[]) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); rc public.craft_recipes; n int; good int;
begin
  select * into rc from public.craft_recipes where id = p_recipe and active;
  if not found then raise exception 'unknown_recipe'; end if;
  n := coalesce(array_length(p_ids, 1), 0);
  if n <> rc.input_qty or (select count(distinct x) from unnest(p_ids) x) <> n then raise exception 'bad_craft_items'; end if;
  perform 1 from public.cards_owned where id = any (p_ids) order by id for update;
  select count(*) into good from public.cards_owned co join public.card_defs d on d.id = co.def_id
   where co.id = any (p_ids) and co.owner = me.id and co.status = 'owned' and d.rarity = rc.input_rarity;
  if good <> n then raise exception 'bad_craft_items'; end if;
  update public.cards_owned set status = 'burned' where id = any (p_ids);
  perform public._add_pack(me.id, rc.output_pack, 1);
  return jsonb_build_object('pack', rc.output_pack, 'me', public.get_me());
end $$;
