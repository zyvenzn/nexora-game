-- =====================================================================
-- Part 5: lock everything down
-- Players can only call the functions listed here. They cannot read or
-- write any table directly, so the browser cannot invent cards or coins.
-- =====================================================================

-- 1. Tables: row level security on, no policies, no direct privileges.
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
    execute format('revoke all on table public.%I from anon, authenticated', t.tablename);
  end loop;
  for t in select sequencename from pg_sequences where schemaname = 'public' loop
    execute format('revoke all on sequence public.%I from anon, authenticated', t.sequencename);
  end loop;
end $$;

-- 2. Functions: nobody by default; helpers (names starting with "_") stay private.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if left(f.proname, 1) <> '_' then
      execute format('grant execute on function %s to authenticated', f.sig);
      if f.proname = any (array['username_available', 'get_catalog', 'feed_recent', 'market_browse',
                                'auction_browse', 'get_leaderboard', 'get_public_profile']) then
        execute format('grant execute on function %s to anon', f.sig);
      end if;
    end if;
  end loop;
end $$;
