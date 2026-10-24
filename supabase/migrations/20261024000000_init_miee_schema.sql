-- Migration: Initial Miee Schema (Profiles, Playlists, Tracks, Liked Songs, Rooms, Room Members, Room State)
-- Created: 2026-10-24

-- 1. Profiles Table
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text default 'Miee Listener',
  username text unique,
  avatar_url text,
  profile_picture_path text,
  favorite_genre text default 'Acoustic',
  favorite_artist text default 'Unknown Artist',
  selected_artist_ids jsonb default '[]'::jsonb,
  selected_artists jsonb default '[]'::jsonb,
  onboarding_completed boolean default false,
  playback_speed double precision default 1.0,
  preferred_source text default 'preferLocal',
  default_shuffle boolean default false,
  default_repeat text default 'off',
  resume_playback boolean default true,
  background_playback boolean default true,
  media_notification boolean default true,
  lock_screen_controls boolean default true,
  gapless_playback boolean default true,
  crossfade boolean default false,
  last_scan_time text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

create policy "Users can insert own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

-- Auto-provision profile on new auth user
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'full_name', 'Miee Listener')
  )
  on conflict (id) do update set
    email = excluded.email,
    display_name = coalesce(excluded.display_name, public.profiles.display_name);
  return new;
end;
$$ language plpgsql security definer;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- 2. Playlists Table
create table if not exists public.playlists (
  id text primary key default gen_random_uuid()::text,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  custom_cover_path text,
  created_at timestamptz default now(),
  last_modified timestamptz default now()
);

alter table public.playlists enable row level security;

create policy "Users can view own playlists"
  on public.playlists for select
  using (auth.uid() = user_id);

create policy "Users can insert own playlists"
  on public.playlists for insert
  with check (auth.uid() = user_id);

create policy "Users can update own playlists"
  on public.playlists for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete own playlists"
  on public.playlists for delete
  using (auth.uid() = user_id);

create index if not exists idx_playlists_user_id on public.playlists(user_id);


-- 3. Playlist Tracks Table (deterministic ordering)
create table if not exists public.playlist_tracks (
  id text primary key default gen_random_uuid()::text,
  playlist_id text not null references public.playlists(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  track_id text not null,
  title text not null,
  artist text not null,
  image_url text,
  duration_ms integer default 0,
  file_path text,
  is_youtube boolean default false,
  position integer not null default 0,
  added_at timestamptz default now(),
  constraint uq_playlist_track unique(playlist_id, track_id)
);

alter table public.playlist_tracks enable row level security;

create policy "Users can view own playlist tracks"
  on public.playlist_tracks for select
  using (auth.uid() = user_id);

create policy "Users can insert own playlist tracks"
  on public.playlist_tracks for insert
  with check (auth.uid() = user_id);

create policy "Users can update own playlist tracks"
  on public.playlist_tracks for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete own playlist tracks"
  on public.playlist_tracks for delete
  using (auth.uid() = user_id);

create index if not exists idx_playlist_tracks_playlist_pos on public.playlist_tracks(playlist_id, position);


-- 4. Liked Songs Table (unique per user and track)
create table if not exists public.liked_songs (
  id text primary key default gen_random_uuid()::text,
  user_id uuid not null references auth.users(id) on delete cascade,
  track_id text not null,
  title text not null,
  artist text not null,
  image_url text,
  duration_ms integer default 0,
  file_path text,
  is_youtube boolean default false,
  liked_at timestamptz default now(),
  constraint uq_user_track_like unique(user_id, track_id)
);

alter table public.liked_songs enable row level security;

create policy "Users can view own liked songs"
  on public.liked_songs for select
  using (auth.uid() = user_id);

create policy "Users can insert own liked songs"
  on public.liked_songs for insert
  with check (auth.uid() = user_id);

create policy "Users can delete own liked songs"
  on public.liked_songs for delete
  using (auth.uid() = user_id);

create index if not exists idx_liked_songs_user_id on public.liked_songs(user_id);


-- 5. Rooms Table (capacity constrained to 1-5, host, unique join code)
create table if not exists public.rooms (
  id text primary key default gen_random_uuid()::text,
  host_id uuid not null references auth.users(id) on delete cascade,
  join_code text not null unique,
  name text not null,
  status text not null default 'active' check (status in ('active', 'ended', 'paused')),
  capacity integer not null default 5 check (capacity >= 1 and capacity <= 5),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.rooms enable row level security;


-- 6. Room Members Table (unique room/user membership, role)
create table if not exists public.room_members (
  id text primary key default gen_random_uuid()::text,
  room_id text not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'listener' check (role in ('host', 'listener')),
  joined_at timestamptz default now(),
  last_seen_at timestamptz default now(),
  constraint uq_room_member unique(room_id, user_id)
);

alter table public.room_members enable row level security;


-- Now attach policies for Rooms and Room Members
create policy "Users can view active rooms or joined rooms"
  on public.rooms for select
  using (
    auth.uid() is not null
    and (
      host_id = auth.uid()
      or status = 'active'
      or exists (
        select 1 from public.room_members rm
        where rm.room_id = public.rooms.id and rm.user_id = auth.uid()
      )
    )
  );

create policy "Host can create rooms"
  on public.rooms for insert
  with check (auth.uid() = host_id);

create policy "Host can update own room"
  on public.rooms for update
  using (auth.uid() = host_id)
  with check (auth.uid() = host_id);

create policy "Host can delete own room"
  on public.rooms for delete
  using (auth.uid() = host_id);

create policy "Members can view room members"
  on public.room_members for select
  using (
    auth.uid() is not null
    and (
      user_id = auth.uid()
      or exists (
        select 1 from public.room_members rm
        where rm.room_id = public.room_members.room_id and rm.user_id = auth.uid()
      )
      or exists (
        select 1 from public.rooms r
        where r.id = public.room_members.room_id and r.host_id = auth.uid()
      )
    )
  );

create policy "Users can join or host can add"
  on public.room_members for insert
  with check (
    auth.uid() is not null
    and (
      user_id = auth.uid()
      or exists (
        select 1 from public.rooms r
        where r.id = room_id and r.host_id = auth.uid()
      )
    )
  );

create policy "Self or host can remove member"
  on public.room_members for delete
  using (
    auth.uid() is not null
    and (
      user_id = auth.uid()
      or exists (
        select 1 from public.rooms r
        where r.id = public.room_members.room_id and r.host_id = auth.uid()
      )
    )
  );


-- 7. Server-side Atomic Room Join Function (enforcing capacity 1-5 counting host, preventing race conditions)
create or replace function public.join_room(p_join_code text)
returns jsonb as $$
declare
  v_room public.rooms%rowtype;
  v_current_count integer;
  v_user_id uuid;
  v_member_role text;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Lock room row for update to ensure atomic capacity check
  select * into v_room
  from public.rooms
  where join_code = upper(trim(p_join_code)) and status = 'active'
  for update;

  if not found then
    return jsonb_build_object('success', false, 'error', 'Room not found or not active');
  end if;

  -- If already a member, return existing membership
  if exists (select 1 from public.room_members where room_id = v_room.id and user_id = v_user_id) then
    select role into v_member_role from public.room_members where room_id = v_room.id and user_id = v_user_id;
    return jsonb_build_object('success', true, 'room_id', v_room.id, 'role', v_member_role);
  end if;

  -- Count total members (including host)
  select count(*) into v_current_count
  from public.room_members
  where room_id = v_room.id;

  if v_current_count >= v_room.capacity then
    return jsonb_build_object('success', false, 'error', 'Room is at full capacity (' || v_room.capacity || ' max)');
  end if;

  v_member_role := case when v_room.host_id = v_user_id then 'host' else 'listener' end;

  insert into public.room_members (room_id, user_id, role)
  values (v_room.id, v_user_id, v_member_role);

  return jsonb_build_object('success', true, 'room_id', v_room.id, 'role', v_member_role);
end;
$$ language plpgsql security definer;


-- 8. Room State Table (canonical track identity, queue, status, host-controlled)
create table if not exists public.room_state (
  room_id text primary key references public.rooms(id) on delete cascade,
  current_track_id text,
  title text,
  artist text,
  image_url text,
  duration_ms integer default 0,
  is_youtube boolean default true,
  queue jsonb default '[]'::jsonb,
  playback_status text default 'paused' check (playback_status in ('playing', 'paused', 'buffering', 'stopped')),
  position_ms integer default 0,
  updated_at timestamptz default now(),
  updated_by uuid references auth.users(id)
);

alter table public.room_state enable row level security;

create policy "Room members can view room state"
  on public.room_state for select
  using (
    auth.uid() is not null
    and (
      exists (
        select 1 from public.rooms r
        where r.id = public.room_state.room_id and r.host_id = auth.uid()
      )
      or exists (
        select 1 from public.room_members rm
        where rm.room_id = public.room_state.room_id and rm.user_id = auth.uid()
      )
    )
  );

create policy "Host can insert room state"
  on public.room_state for insert
  with check (
    auth.uid() is not null
    and exists (
      select 1 from public.rooms r
      where r.id = room_id and r.host_id = auth.uid()
    )
  );

create policy "Host can update room state"
  on public.room_state for update
  using (
    auth.uid() is not null
    and exists (
      select 1 from public.rooms r
      where r.id = public.room_state.room_id and r.host_id = auth.uid()
    )
  )
  with check (
    auth.uid() is not null
    and exists (
      select 1 from public.rooms r
      where r.id = public.room_state.room_id and r.host_id = auth.uid()
    )
  );


-- 9. Realtime Publication Setup
alter publication supabase_realtime add table public.rooms;
alter publication supabase_realtime add table public.room_members;
alter publication supabase_realtime add table public.room_state;
