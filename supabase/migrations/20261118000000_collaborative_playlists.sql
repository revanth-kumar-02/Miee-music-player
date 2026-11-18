-- Migration: 20261118000000_collaborative_playlists.sql
-- Description:
-- 1. Upgrade playlists table to support types (private, shared, collaborative), descriptions, and versioning.
-- 2. Create playlist_members table for Role-Based Access Control (owner, editor, viewer).
-- 3. Create playlist_invitations table for secure, tokenized invite links.
-- 4. Create SECURITY DEFINER helper functions to eliminate RLS recursion.
-- 5. Establish high-performance, non-recursive RLS policies across playlists, playlist_tracks, and members.
-- 6. Implement atomic RPC functions: accept_playlist_invitation and reorder_playlist_tracks.

-- ============================================================================
-- 1. Upgrade Playlists Table
-- ============================================================================

alter table public.playlists
  add column if not exists description text default '',
  add column if not exists type text not null default 'private' check (type in ('private', 'shared', 'collaborative')),
  add column if not exists version bigint not null default 1;

create index if not exists idx_playlists_type on public.playlists(type);

-- ============================================================================
-- 2. Playlist Members Table
-- ============================================================================

create table if not exists public.playlist_members (
  id text primary key default gen_random_uuid()::text,
  playlist_id text not null references public.playlists(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'editor', 'viewer')),
  joined_at timestamptz not null default now(),
  constraint uq_playlist_member unique(playlist_id, user_id)
);

create index if not exists idx_playlist_members_user_id on public.playlist_members(user_id);
create index if not exists idx_playlist_members_playlist_id on public.playlist_members(playlist_id);

alter table public.playlist_members enable row level security;

-- ============================================================================
-- 3. Playlist Invitations Table
-- ============================================================================

create table if not exists public.playlist_invitations (
  id text primary key default gen_random_uuid()::text,
  playlist_id text not null references public.playlists(id) on delete cascade,
  token text not null unique,
  role text not null default 'editor' check (role in ('editor', 'viewer')),
  created_by uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  max_uses integer default 10,
  uses_count integer default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists idx_playlist_invitations_token on public.playlist_invitations(token);
create index if not exists idx_playlist_invitations_playlist_id on public.playlist_invitations(playlist_id);

alter table public.playlist_invitations enable row level security;

-- ============================================================================
-- 4. SECURITY DEFINER Helper Functions
-- ============================================================================

create or replace function public.is_playlist_member(p_playlist_id text, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.playlist_members
    where playlist_id = p_playlist_id and user_id = p_user_id
  );
$$;

revoke all on function public.is_playlist_member(text, uuid) from public;
grant execute on function public.is_playlist_member(text, uuid) to authenticated, service_role;

create or replace function public.is_playlist_editor(p_playlist_id text, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.playlist_members
    where playlist_id = p_playlist_id and user_id = p_user_id and role in ('owner', 'editor')
  );
$$;

revoke all on function public.is_playlist_editor(text, uuid) from public;
grant execute on function public.is_playlist_editor(text, uuid) to authenticated, service_role;

create or replace function public.is_playlist_owner(p_playlist_id text, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.playlists
    where id = p_playlist_id and user_id = p_user_id
  );
$$;

revoke all on function public.is_playlist_owner(text, uuid) from public;
grant execute on function public.is_playlist_owner(text, uuid) to authenticated, service_role;

-- ============================================================================
-- 5. Updated RLS Policies for Playlists
-- ============================================================================

drop policy if exists "Users can view own playlists" on public.playlists;
create policy "Users can view own or member playlists"
  on public.playlists for select
  using (
    (select auth.uid()) is not null
    and (
      user_id = (select auth.uid())
      or type in ('shared', 'collaborative')
      or public.is_playlist_member(id, (select auth.uid()))
    )
  );

drop policy if exists "Users can update own playlists" on public.playlists;
create policy "Owners and editors can update playlists"
  on public.playlists for update
  using (
    (select auth.uid()) is not null
    and (
      user_id = (select auth.uid())
      or public.is_playlist_editor(id, (select auth.uid()))
    )
  )
  with check (
    (select auth.uid()) is not null
    and (
      user_id = (select auth.uid())
      or public.is_playlist_editor(id, (select auth.uid()))
    )
  );

-- ============================================================================
-- 6. Updated RLS Policies for Playlist Tracks
-- ============================================================================

drop policy if exists "Users can view own playlist tracks" on public.playlist_tracks;
create policy "Users can view own or member playlist tracks"
  on public.playlist_tracks for select
  using (
    (select auth.uid()) is not null
    and (
      user_id = (select auth.uid())
      or public.is_playlist_member(playlist_id, (select auth.uid()))
      or exists (
        select 1 from public.playlists p
        where p.id = playlist_id and p.type in ('shared', 'collaborative')
      )
    )
  );

drop policy if exists "Users can insert own playlist tracks" on public.playlist_tracks;
create policy "Owners and editors can insert playlist tracks"
  on public.playlist_tracks for insert
  with check (
    (select auth.uid()) is not null
    and (
      user_id = (select auth.uid())
      or public.is_playlist_editor(playlist_id, (select auth.uid()))
    )
  );

drop policy if exists "Users can update own playlist tracks" on public.playlist_tracks;
create policy "Owners and editors can update playlist tracks"
  on public.playlist_tracks for update
  using (
    (select auth.uid()) is not null
    and (
      user_id = (select auth.uid())
      or public.is_playlist_editor(playlist_id, (select auth.uid()))
    )
  )
  with check (
    (select auth.uid()) is not null
    and (
      user_id = (select auth.uid())
      or public.is_playlist_editor(playlist_id, (select auth.uid()))
    )
  );

drop policy if exists "Users can delete own playlist tracks" on public.playlist_tracks;
create policy "Owners and editors can delete playlist tracks"
  on public.playlist_tracks for delete
  using (
    (select auth.uid()) is not null
    and (
      user_id = (select auth.uid())
      or public.is_playlist_editor(playlist_id, (select auth.uid()))
    )
  );

-- ============================================================================
-- 7. RLS Policies for Playlist Members
-- ============================================================================

create policy "Members can view other members in same playlist"
  on public.playlist_members for select
  using (
    (select auth.uid()) is not null
    and (
      user_id = (select auth.uid())
      or public.is_playlist_member(playlist_id, (select auth.uid()))
    )
  );

create policy "Owners can manage playlist members"
  on public.playlist_members for all
  using (
    (select auth.uid()) is not null
    and public.is_playlist_owner(playlist_id, (select auth.uid()))
  )
  with check (
    (select auth.uid()) is not null
    and public.is_playlist_owner(playlist_id, (select auth.uid()))
  );

create policy "Members can leave playlist"
  on public.playlist_members for delete
  using (
    (select auth.uid()) is not null
    and user_id = (select auth.uid())
  );

-- ============================================================================
-- 8. RLS Policies for Playlist Invitations
-- ============================================================================

create policy "Members can view active invitations"
  on public.playlist_invitations for select
  using (
    (select auth.uid()) is not null
    and (
      public.is_playlist_member(playlist_id, (select auth.uid()))
      or public.is_playlist_owner(playlist_id, (select auth.uid()))
    )
  );

create policy "Owners can create and manage invitations"
  on public.playlist_invitations for all
  using (
    (select auth.uid()) is not null
    and public.is_playlist_owner(playlist_id, (select auth.uid()))
  )
  with check (
    (select auth.uid()) is not null
    and public.is_playlist_owner(playlist_id, (select auth.uid()))
  );

-- ============================================================================
-- 9. Atomic RPC Functions
-- ============================================================================

-- A. Accept Playlist Invitation
create or replace function public.accept_playlist_invitation(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_invitation record;
  v_playlist record;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Authentication required to accept playlist invitation.';
  end if;

  select * into v_invitation
  from public.playlist_invitations
  where token = p_token
    and is_active = true
    and expires_at > now()
  for update;

  if not found then
    raise exception 'Invitation is invalid, expired, or has been revoked.';
  end if;

  if v_invitation.max_uses is not null and v_invitation.uses_count >= v_invitation.max_uses then
    raise exception 'Invitation has reached maximum usage limit.';
  end if;

  select * into v_playlist
  from public.playlists
  where id = v_invitation.playlist_id;

  if not found then
    raise exception 'Playlist no longer exists.';
  end if;

  -- Add user as member with assigned role (or maintain role if already member)
  insert into public.playlist_members (playlist_id, user_id, role, joined_at)
  values (v_invitation.playlist_id, v_user_id, v_invitation.role, now())
  on conflict (playlist_id, user_id) do update
  set role = case
    when playlist_members.role = 'owner' then 'owner'
    else excluded.role
  end;

  -- Increment use count
  update public.playlist_invitations
  set uses_count = uses_count + 1
  where id = v_invitation.id;

  return jsonb_build_object(
    'success', true,
    'playlist_id', v_playlist.id,
    'playlist_name', v_playlist.name,
    'role', v_invitation.role
  );
end;
$$;

revoke all on function public.accept_playlist_invitation(text) from public;
grant execute on function public.accept_playlist_invitation(text) to authenticated, service_role;

-- B. Atomic Track Position Reordering
create or replace function public.reorder_playlist_tracks(
  p_playlist_id text,
  p_positions jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_item jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if not (public.is_playlist_owner(p_playlist_id, v_user_id) or public.is_playlist_editor(p_playlist_id, v_user_id)) then
    raise exception 'Insufficient permissions to reorder tracks in this playlist.';
  end if;

  for v_item in select * from jsonb_array_elements(p_positions)
  loop
    update public.playlist_tracks
    set position = (v_item->>'position')::integer
    where playlist_id = p_playlist_id
      and track_id = (v_item->>'trackId');
  end loop;

  update public.playlists
  set last_modified = now(),
      version = version + 1
  where id = p_playlist_id;
end;
$$;

revoke all on function public.reorder_playlist_tracks(text, jsonb) from public;
grant execute on function public.reorder_playlist_tracks(text, jsonb) to authenticated, service_role;
