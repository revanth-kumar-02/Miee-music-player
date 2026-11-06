-- Migration: 20261105000000_scalability_indexes.sql
-- Description:
-- REM-01: Critical compound and foreign-key indexes to eliminate sequential scans,
-- optimize synchronization queries, and support high-throughput room messaging.

-- 1. Index playlist_tracks by user_id
-- Eliminates sequential scans during SyncManager library synchronization and foreign key cascading.
create index if not exists idx_playlist_tracks_user_id
  on public.playlist_tracks(user_id);

-- 2. Index room_messages by room_id and created_at ascending
-- Enables index-only/index scans for chronological room chat history queries without sorting.
create index if not exists idx_room_messages_room_created
  on public.room_messages(room_id, created_at asc);

-- 3. Composite index on liked_songs for user_id and liked_at descending
-- Optimizes delta-sync queries and chronological favorites retrieval.
create index if not exists idx_liked_songs_user_liked_at
  on public.liked_songs(user_id, liked_at desc);


-- 4. REM-08: RLS Update Policy on liked_songs
-- Enables PostgREST upsert (Prefer: resolution=merge-duplicates) on liked_songs without HTTP 403 errors.
do $$
begin
  if not exists (
    select 1 from pg_policies 
    where tablename = 'liked_songs' and policyname = 'Users can update own liked songs'
  ) then
    create policy "Users can update own liked songs"
      on public.liked_songs for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
end $$;

-- 5. REM-07 & REM-08: Automatic Parent Playlist last_modified Trigger
-- Automatically bumps playlists.last_modified whenever child tracks are added, updated, or removed.
create or replace function public.fn_sync_playlist_last_modified()
returns trigger as $$
begin
  if (tg_op = 'DELETE') then
    update public.playlists
    set last_modified = now()
    where id = old.playlist_id;
    return old;
  else
    update public.playlists
    set last_modified = now()
    where id = new.playlist_id;
    return new;
  end if;
end;
$$ language plpgsql security definer;

drop trigger if exists on_playlist_track_change on public.playlist_tracks;
create trigger on_playlist_track_change
after insert or update or delete on public.playlist_tracks
for each row execute function public.fn_sync_playlist_last_modified();
