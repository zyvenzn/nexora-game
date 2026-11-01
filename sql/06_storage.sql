-- =====================================================================
-- Part 6: storage for profile pictures and banners (public bucket, own folder only)
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profiles', 'profiles', true, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = 2097152,
  allowed_mime_types = array['image/png', 'image/jpeg', 'image/webp'];

drop policy if exists "nexora profiles read" on storage.objects;
drop policy if exists "nexora profiles insert own" on storage.objects;
drop policy if exists "nexora profiles update own" on storage.objects;
drop policy if exists "nexora profiles delete own" on storage.objects;

create policy "nexora profiles read" on storage.objects
  for select using (bucket_id = 'profiles');
create policy "nexora profiles insert own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'profiles' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "nexora profiles update own" on storage.objects
  for update to authenticated
  using (bucket_id = 'profiles' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'profiles' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "nexora profiles delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'profiles' and (storage.foldername(name))[1] = auth.uid()::text);
