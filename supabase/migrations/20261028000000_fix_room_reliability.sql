-- Migration: 20261028000000_fix_room_reliability.sql
-- Description:
-- 1. Add revision sequence number to room_state for authoritative monotonic synchronization.
-- 2. Allow authenticated users to view public profile info (display_name, username, avatar_url)
--    so room participants can see actual usernames instead of generic placeholders.
-- 3. Set REPLICA IDENTITY FULL on room_messages, room_state, and room_members to ensure full CDC payload.
-- 4. Ensure realtime publication includes all room tables.

-- 1. Add revision column to room_state
alter table public.room_state
  add column if not exists revision bigint not null default 1;

-- 2. Allow authenticated users to view profiles
drop policy if exists "Authenticated users can view profiles" on public.profiles;
create policy "Authenticated users can view profiles"
  on public.profiles for select
  using (auth.uid() is not null);

-- 3. Set REPLICA IDENTITY FULL for real-time CDC filtering and full payloads
alter table public.room_messages replica identity full;
alter table public.room_state replica identity full;
alter table public.room_members replica identity full;

-- 4. Realtime publication check
do $$
begin
  if not exists (
    select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'room_messages'
  ) then
    alter publication supabase_realtime add table public.room_messages;
  end if;
  if not exists (
    select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'room_state'
  ) then
    alter publication supabase_realtime add table public.room_state;
  end if;
  if not exists (
    select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'room_members'
  ) then
    alter publication supabase_realtime add table public.room_members;
  end if;
end $$;
