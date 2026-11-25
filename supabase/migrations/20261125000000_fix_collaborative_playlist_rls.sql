-- Migration: 20261125000000_fix_collaborative_playlist_rls.sql
-- Description:
-- Restrict SELECT RLS policies on public.playlists and public.playlist_tracks
-- so 'shared' and 'collaborative' playlists are only readable by owners or
-- explicit playlist_members (fixing CRIT-02 global read leak).

drop policy if exists "Users can view own or member playlists" on public.playlists;
create policy "Users can view own or member playlists"
  on public.playlists for select
  using (
    (select auth.uid()) is not null
    and (
      user_id = (select auth.uid())
      or public.is_playlist_member(id, (select auth.uid()))
    )
  );

drop policy if exists "Users can view own or member playlist tracks" on public.playlist_tracks;
create policy "Users can view own or member playlist tracks"
  on public.playlist_tracks for select
  using (
    (select auth.uid()) is not null
    and (
      user_id = (select auth.uid())
      or public.is_playlist_member(playlist_id, (select auth.uid()))
      or public.is_playlist_owner(playlist_id, (select auth.uid()))
    )
  );
