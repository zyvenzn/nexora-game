-- =====================================================================
-- Part 4: leaderboard, public profiles, admin panel
-- =====================================================================

-- ---------- scores ----------
create or replace function public._scores() returns table (
  user_id uuid, score bigint, total int, uniq int, best_rank int)
language sql stable security definer set search_path = public, pg_temp as $$
  select co.owner, sum(r.score)::bigint, count(*)::int, count(distinct co.def_id)::int, max(r.rank)::int
    from public.cards_owned co
    join public.card_defs d on d.id = co.def_id
    join public.rarities r on r.id = d.rarity
   where co.status <> 'burned'
   group by co.owner
$$;

create or replace function public.get_leaderboard(p_limit int default 50, p_mode text default 'score') returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  with s as (
    select * from public._scores()
  ), ranked as (
    select s.*, p.username, p.display_name, p.avatar_url,
           row_number() over (order by
             case when p_mode = 'rarest' then s.best_rank end desc nulls last,
             case when p_mode = 'collectors' then s.uniq end desc nulls last,
             s.score desc, s.total desc, p.created_at) as pos
      from s join public.profiles p on p.id = s.user_id
     where not p.banned
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'pos', pos, 'username', username, 'display_name', display_name, 'avatar_url', avatar_url,
      'score', score, 'total', total, 'unique', uniq,
      'rarest', (select jsonb_build_object('name', d.name, 'rarity', d.rarity, 'serial', co.serial, 'def_id', d.id)
                   from public.cards_owned co join public.card_defs d on d.id = co.def_id join public.rarities r on r.id = d.rarity
                  where co.owner = ranked.user_id and co.status <> 'burned'
                  order by r.rank desc, co.serial limit 1)
    ) order by pos), '[]'::jsonb)
  from ranked where pos <= least(greatest(p_limit, 1), 100)
$$;

create or replace function public.get_public_profile(p_username text) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare p public.profiles; sc record; pos int; active_defs int;
begin
  select * into p from public.profiles where lower(username) = lower(trim(coalesce(p_username, '')));
  if not found then raise exception 'no_such_player'; end if;
  select * into sc from public._scores() where user_id = p.id;
  select count(*) + 1 into pos from public._scores() x join public.profiles q on q.id = x.user_id
   where not q.banned and x.score > coalesce(sc.score, 0);
  select count(*) into active_defs from public.card_defs where active;
  return jsonb_build_object(
    'username', p.username, 'display_name', p.display_name, 'bio', p.bio,
    'avatar_url', p.avatar_url, 'banner_url', p.banner_url, 'banned', p.banned, 'created_at', p.created_at,
    'score', coalesce(sc.score, 0), 'total', coalesce(sc.total, 0), 'unique', coalesce(sc.uniq, 0),
    'completion', case when active_defs = 0 then 0 else round(100.0 * coalesce(sc.uniq, 0) / active_defs) end,
    'rank', case when p.banned then null else pos end,
    'trades_done', (select count(*) from public.trades x where x.status = 'accepted' and (x.from_user = p.id or x.to_user = p.id)),
    'showcase', (select coalesce(jsonb_agg(public._card_obj(id) order by rk desc, serial), '[]'::jsonb)
                   from (select co.id, r.rank as rk, co.serial from public.cards_owned co
                           join public.card_defs d on d.id = co.def_id join public.rarities r on r.id = d.rarity
                          where co.owner = p.id and co.status <> 'burned'
                          order by r.rank desc, co.serial limit 12) q),
    'for_sale', (select count(*) from public.listings where seller = p.id and status = 'active'));
end $$;

-- Someone else's tradable cards (for building a trade offer).
create or replace function public.player_cards(p_username text) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); p public.profiles;
begin
  select * into p from public.profiles where lower(username) = lower(trim(coalesce(p_username, '')));
  if not found then raise exception 'no_such_player'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', co.id, 'def_id', co.def_id, 'serial', co.serial) order by r.rank desc, co.serial)
                     from public.cards_owned co join public.card_defs d on d.id = co.def_id join public.rarities r on r.id = d.rarity
                    where co.owner = p.id and co.status = 'owned'), '[]'::jsonb);
end $$;

-- ---------- admin ----------
create or replace function public.admin_overview() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  return jsonb_build_object(
    'players', (select count(*) from public.profiles),
    'banned', (select count(*) from public.profiles where banned),
    'cards', (select count(*) from public.cards_owned where status <> 'burned'),
    'stardust', (select coalesce(sum(balance), 0) from public.profiles),
    'listings', (select count(*) from public.listings where status = 'active'),
    'auctions', (select count(*) from public.auctions where status = 'active'),
    'trades_open', (select count(*) from public.trades where status = 'pending'),
    'reports_open', (select count(*) from public.reports where status = 'open'),
    'packs_opened', (select count(*) from public.pack_openings),
    'sales_24h', (select count(*) from public.sales where at > now() - interval '1 day'));
end $$;

create or replace function public.admin_users(p_search text default '', p_limit int default 30) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'username', username, 'display_name', display_name,
            'balance', balance, 'role', role, 'banned', banned, 'ban_reason', ban_reason, 'created_at', created_at,
            'cards', (select count(*) from public.cards_owned co where co.owner = q.id and co.status <> 'burned')) order by created_at desc)
          from (select * from public.profiles
                 where coalesce(p_search, '') = '' or username ilike '%' || replace(replace(p_search, '%', ''), '_', '') || '%'
                 order by created_at desc limit least(greatest(p_limit, 1), 100)) q), '[]'::jsonb);
end $$;

create or replace function public.admin_grant_coins(p_username text, p_amount bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); t public.profiles; nb bigint;
begin
  select * into t from public.profiles where lower(username) = lower(trim(p_username));
  if not found then raise exception 'no_such_player'; end if;
  if p_amount is null or p_amount = 0 or abs(p_amount) > 1000000 then raise exception 'bad_amount'; end if;
  nb := public._coins(t.id, p_amount, 'admin', left(coalesce(p_reason, ''), 100));
  perform public._audit('grant_coins', t.username, jsonb_build_object('amount', p_amount, 'reason', p_reason));
  return jsonb_build_object('balance', nb);
end $$;

create or replace function public.admin_give_pack(p_username text, p_pack text, p_qty int default 1) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); t public.profiles;
begin
  select * into t from public.profiles where lower(username) = lower(trim(p_username));
  if not found then raise exception 'no_such_player'; end if;
  if not exists (select 1 from public.pack_types where id = p_pack) then raise exception 'unknown_pack'; end if;
  if p_qty is null or p_qty < 1 or p_qty > 100 then raise exception 'bad_quantity'; end if;
  perform public._add_pack(t.id, p_pack, p_qty);
  perform public._audit('give_pack', t.username, jsonb_build_object('pack', p_pack, 'qty', p_qty));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_give_card(p_username text, p_def text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); t public.profiles; iid uuid;
begin
  select * into t from public.profiles where lower(username) = lower(trim(p_username));
  if not found then raise exception 'no_such_player'; end if;
  if not exists (select 1 from public.card_defs where id = p_def) then raise exception 'unknown_card'; end if;
  iid := public._mint(t.id, p_def, 'admin');
  perform public._audit('give_card', t.username, jsonb_build_object('def', p_def, 'instance', iid));
  return jsonb_build_object('instance_id', iid);
end $$;

create or replace function public.admin_set_ban(p_username text, p_banned boolean, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); t public.profiles; l record; au record;
begin
  select * into t from public.profiles where lower(username) = lower(trim(p_username));
  if not found then raise exception 'no_such_player'; end if;
  if t.role = 'admin' then raise exception 'cannot_ban_admin'; end if;
  update public.profiles set banned = coalesce(p_banned, false), ban_reason = case when p_banned then left(p_reason, 200) else null end where id = t.id;
  if p_banned then
    -- free their cards from deals so nothing stays stuck
    for l in select id from public.listings where seller = t.id and status = 'active' loop
      update public.listings set status = 'cancelled' where id = l.id;
    end loop;
    update public.cards_owned set status = 'owned' where owner = t.id and status = 'listed';
    for au in select id from public.auctions where seller = t.id and status = 'active' and bid_count = 0 loop
      update public.auctions set status = 'cancelled', settled_at = now() where id = au.id;
    end loop;
    update public.cards_owned set status = 'owned' where owner = t.id and status = 'auction'
      and id not in (select instance_id from public.auctions where status = 'active');
    perform public._trade_release(x.id, 'cancelled') from public.trades x where x.from_user = t.id and x.status = 'pending';
  end if;
  perform public._audit(case when p_banned then 'ban' else 'unban' end, t.username, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_upsert_card(p_def jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); cid text := lower(trim(p_def ->> 'id'));
begin
  if cid is null or cid !~ '^[a-z0-9-]{3,40}$' then raise exception 'bad_card_id'; end if;
  insert into public.card_defs (id, name, rarity, element, image, blurb, base_price, active)
  values (cid, p_def ->> 'name', p_def ->> 'rarity', p_def ->> 'element', p_def ->> 'image',
          coalesce(p_def ->> 'blurb', ''), nullif(p_def ->> 'base_price', '')::int, coalesce((p_def ->> 'active')::boolean, true))
  on conflict (id) do update set name = excluded.name, rarity = excluded.rarity, element = excluded.element,
     image = excluded.image, blurb = excluded.blurb, base_price = excluded.base_price, active = excluded.active;
  perform public._audit('upsert_card', cid, p_def);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_upsert_pack(p_pack jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); pid text := lower(trim(p_pack ->> 'id'));
begin
  if pid is null or pid !~ '^[a-z0-9-]{3,30}$' then raise exception 'bad_pack_id'; end if;
  insert into public.pack_types (id, name, description, element, price, cards_count, odds, guarantee_rarity, element_bias, purchasable, active, sort)
  values (pid, p_pack ->> 'name', coalesce(p_pack ->> 'description', ''), nullif(p_pack ->> 'element', ''),
          coalesce((p_pack ->> 'price')::int, 100), coalesce((p_pack ->> 'cards_count')::int, 4), coalesce(p_pack -> 'odds', '{"common":100}'::jsonb),
          nullif(p_pack ->> 'guarantee_rarity', ''), coalesce((p_pack ->> 'element_bias')::int, 3),
          coalesce((p_pack ->> 'purchasable')::boolean, true), coalesce((p_pack ->> 'active')::boolean, true), coalesce((p_pack ->> 'sort')::int, 10))
  on conflict (id) do update set name = excluded.name, description = excluded.description, element = excluded.element,
     price = excluded.price, cards_count = excluded.cards_count, odds = excluded.odds, guarantee_rarity = excluded.guarantee_rarity,
     element_bias = excluded.element_bias, purchasable = excluded.purchasable, active = excluded.active, sort = excluded.sort;
  perform public._audit('upsert_pack', pid, p_pack);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_set_setting(p_key text, p_value bigint) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  if not exists (select 1 from public.settings where key = p_key) then raise exception 'unknown_setting'; end if;
  if p_value is null or p_value < 0 or p_value > 1000000 then raise exception 'bad_amount'; end if;
  update public.settings set value = to_jsonb(p_value) where key = p_key;
  perform public._audit('set_setting', p_key, to_jsonb(p_value));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_settings() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  return (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from public.settings);
end $$;

create or replace function public.admin_cancel_listing(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); l public.listings;
begin
  select * into l from public.listings where id = p_id for update;
  if not found or l.status <> 'active' then raise exception 'listing_gone'; end if;
  update public.listings set status = 'cancelled' where id = l.id;
  update public.cards_owned set status = 'owned' where id = l.instance_id;
  perform public._audit('cancel_listing', p_id::text, null);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_cancel_auction(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); au public.auctions;
begin
  select * into au from public.auctions where id = p_id for update;
  if not found or au.status <> 'active' then raise exception 'auction_gone'; end if;
  if au.current_bidder is not null then
    perform public._coins(au.current_bidder, au.current_bid, 'bid_refund', au.id::text);
  end if;
  update public.auctions set status = 'cancelled', settled_at = now() where id = au.id;
  update public.cards_owned set status = 'owned' where id = au.instance_id;
  perform public._audit('cancel_auction', p_id::text, null);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_cancel_trade(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  if not exists (select 1 from public.trades where id = p_id and status = 'pending') then raise exception 'trade_closed'; end if;
  perform public._trade_release(p_id, 'cancelled');
  perform public._audit('cancel_trade', p_id::text, null);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_reports(p_status text default 'open') returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'reason', r.reason, 'status', r.status, 'note', r.note,
            'created_at', r.created_at, 'trade_id', r.trade_id,
            'reporter', public._user_json(r.reporter), 'target', public._user_json(r.target)) order by r.created_at desc)
          from public.reports r where r.status = p_status), '[]'::jsonb);
end $$;

create or replace function public.admin_resolve_report(p_id uuid, p_status text, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  if p_status not in ('resolved', 'dismissed') then raise exception 'bad_status'; end if;
  update public.reports set status = p_status, note = left(coalesce(p_note, ''), 300), handled_by = a.id, handled_at = now()
   where id = p_id and status = 'open';
  if not found then raise exception 'report_gone'; end if;
  perform public._audit('resolve_report', p_id::text, jsonb_build_object('status', p_status));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_audit(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'action', l.action, 'target', l.target, 'details', l.details,
            'admin', public._user_json(l.admin_id)) order by l.id desc)
          from (select * from public.audit_log order by id desc limit least(greatest(p_limit, 1), 200)) l), '[]'::jsonb);
end $$;
