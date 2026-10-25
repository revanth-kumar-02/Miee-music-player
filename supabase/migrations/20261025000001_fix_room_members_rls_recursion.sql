-- Migration: 20261025000001_fix_room_members_rls_recursion.sql
-- Description:
-- 1. Create SECURITY DEFINER helper functions (is_room_member, is_room_host) with explicit search_path = public
--    to eliminate recursive RLS evaluation cycles between room_members, rooms, room_state, and room_messages.
-- 2. Redefine RLS policies using the helper functions and auth.uid() checks.
-- 3. Create atomic create_room RPC function enforcing server-side validation (capacity 1-5), transactional integrity,
--    and automatic host membership.
-- 4. Harden join_room with explicit search_path = public.

-- ============================================================================
-- 1. Helper Functions (SECURITY DEFINER with fixed search_path = public)
-- ============================================================================

create or replace function public.is_room_member(p_room_id text, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.room_members
    where room_id = p_room_id and user_id = p_user_id
  );
$$;

revoke all on function public.is_room_member(text, uuid) from public;
grant execute on function public.is_room_member(text, uuid) to authenticated, service_role;

create or replace function public.is_room_host(p_room_id text, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.rooms
    where id = p_room_id and host_id = p_user_id
  );
$$;

revoke all on function public.is_room_host(text, uuid) from public;
grant execute on function public.is_room_host(text, uuid) to authenticated, service_role;


-- ============================================================================
-- 2. Redefine RLS Policies for rooms
-- ============================================================================

drop policy if exists "Users can view active rooms or joined rooms" on public.rooms;
create policy "Users can view active rooms or joined rooms"
  on public.rooms for select
  using (
    auth.uid() is not null
    and (
      host_id = auth.uid()
      or status = 'active'
      or public.is_room_member(id, auth.uid())
    )
  );

drop policy if exists "Host can create rooms" on public.rooms;
create policy "Host can create rooms"
  on public.rooms for insert
  with check (
    auth.uid() is not null
    and auth.uid() = host_id
    and capacity >= 1
    and capacity <= 5
  );

drop policy if exists "Host can update own room" on public.rooms;
create policy "Host can update own room"
  on public.rooms for update
  using (auth.uid() is not null and auth.uid() = host_id)
  with check (auth.uid() is not null and auth.uid() = host_id);

drop policy if exists "Host can delete own room" on public.rooms;
create policy "Host can delete own room"
  on public.rooms for delete
  using (auth.uid() is not null and auth.uid() = host_id);


-- ============================================================================
-- 3. Redefine RLS Policies for room_members (Eliminates 42P17 recursion)
-- ============================================================================

drop policy if exists "Members can view room members" on public.room_members;
drop policy if exists "Members and hosts can view room members" on public.room_members;
create policy "Members and hosts can view room members"
  on public.room_members for select
  using (
    auth.uid() is not null
    and (
      user_id = auth.uid()
      or public.is_room_host(room_id, auth.uid())
      or public.is_room_member(room_id, auth.uid())
    )
  );

drop policy if exists "Users can join or host can add" on public.room_members;
drop policy if exists "Users can insert own membership or host can add" on public.room_members;
create policy "Users can insert own membership or host can add"
  on public.room_members for insert
  with check (
    auth.uid() is not null
    and (
      user_id = auth.uid()
      or public.is_room_host(room_id, auth.uid())
    )
  );

drop policy if exists "Self or host can remove member" on public.room_members;
create policy "Self or host can remove member"
  on public.room_members for delete
  using (
    auth.uid() is not null
    and (
      user_id = auth.uid()
      or public.is_room_host(room_id, auth.uid())
    )
  );


-- ============================================================================
-- 4. Redefine RLS Policies for room_state
-- ============================================================================

drop policy if exists "Room members can view room state" on public.room_state;
create policy "Room members can view room state"
  on public.room_state for select
  using (
    auth.uid() is not null
    and (
      public.is_room_host(room_id, auth.uid())
      or public.is_room_member(room_id, auth.uid())
    )
  );

drop policy if exists "Host can insert room state" on public.room_state;
create policy "Host can insert room state"
  on public.room_state for insert
  with check (
    auth.uid() is not null
    and public.is_room_host(room_id, auth.uid())
  );

drop policy if exists "Host can update room state" on public.room_state;
create policy "Host can update room state"
  on public.room_state for update
  using (
    auth.uid() is not null
    and public.is_room_host(room_id, auth.uid())
  )
  with check (
    auth.uid() is not null
    and public.is_room_host(room_id, auth.uid())
  );


-- ============================================================================
-- 5. Redefine RLS Policies for room_messages
-- ============================================================================

drop policy if exists "Room members can view room messages" on public.room_messages;
create policy "Room members can view room messages"
  on public.room_messages for select
  using (
    auth.uid() is not null
    and (
      public.is_room_host(room_id, auth.uid())
      or public.is_room_member(room_id, auth.uid())
    )
  );

drop policy if exists "Room members can insert messages" on public.room_messages;
create policy "Room members can insert messages"
  on public.room_messages for insert
  with check (
    auth.uid() is not null
    and auth.uid() = user_id
    and (
      public.is_room_host(room_id, auth.uid())
      or public.is_room_member(room_id, auth.uid())
    )
  );


-- ============================================================================
-- 6. Atomic Stored Procedure: create_room
-- ============================================================================

create or replace function public.create_room(
  p_name text default 'Miee Jam',
  p_capacity integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_room_id text;
  v_join_code text;
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code_exists boolean;
  v_attempts integer := 0;
  v_now timestamptz := now();
  v_trimmed_name text;
  v_room public.rooms%rowtype;
begin
  -- 1. Ensure authenticated caller
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'User must be authenticated to host a room.' using errcode = '42501';
  end if;

  -- 2. Validate capacity (1 to 5)
  if p_capacity < 1 or p_capacity > 5 then
    raise exception 'Room capacity must be between 1 and 5.' using errcode = '22023';
  end if;

  -- 3. Sanitize room name
  v_trimmed_name := trim(p_name);
  if v_trimmed_name is null or length(v_trimmed_name) = 0 then
    v_trimmed_name := 'Miee Jam';
  elsif length(v_trimmed_name) > 60 then
    v_trimmed_name := substr(v_trimmed_name, 1, 60);
  end if;

  -- 4. Generate unique 6-character join code
  loop
    v_attempts := v_attempts + 1;
    v_join_code := '';
    for i in 1..6 loop
      v_join_code := v_join_code || substr(v_chars, floor(random() * length(v_chars) + 1)::integer, 1);
    end loop;

    select exists (
      select 1 from public.rooms where join_code = v_join_code
    ) into v_code_exists;

    if not v_code_exists then
      exit;
    end if;

    if v_attempts > 10 then
      v_join_code := substr(md5(gen_random_uuid()::text), 1, 6);
      exit;
    end if;
  end loop;

  v_room_id := gen_random_uuid()::text;

  -- 5. Insert Room atomically
  insert into public.rooms (
    id,
    host_id,
    join_code,
    name,
    status,
    capacity,
    created_at,
    updated_at
  ) values (
    v_room_id,
    v_user_id,
    v_join_code,
    v_trimmed_name,
    'active',
    p_capacity,
    v_now,
    v_now
  ) returning * into v_room;

  -- 6. Insert Host Member
  insert into public.room_members (
    room_id,
    user_id,
    role,
    joined_at,
    last_seen_at
  ) values (
    v_room_id,
    v_user_id,
    'host',
    v_now,
    v_now
  );

  -- 7. Initialize Room State
  insert into public.room_state (
    room_id,
    playback_status,
    position_ms,
    queue,
    updated_at,
    updated_by
  ) values (
    v_room_id,
    'paused',
    0,
    '[]'::jsonb,
    v_now,
    v_user_id
  );

  -- Return room data formatted for ListeningRoom.fromMap
  return jsonb_build_object(
    'id', v_room.id,
    'host_id', v_room.host_id,
    'join_code', v_room.join_code,
    'name', v_room.name,
    'status', v_room.status,
    'capacity', v_room.capacity,
    'created_at', v_room.created_at,
    'updated_at', v_room.updated_at
  );
end;
$$;

revoke all on function public.create_room(text, integer) from public;
grant execute on function public.create_room(text, integer) to authenticated, service_role;


-- ============================================================================
-- 7. Hardened join_room (add set search_path = public)
-- ============================================================================

create or replace function public.join_room(p_join_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms%rowtype;
  v_current_count integer;
  v_user_id uuid;
  v_member_role text;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    return jsonb_build_object('success', false, 'error', 'Not authenticated');
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
    return jsonb_build_object('success', false, 'error', 'Room is full');
  end if;

  v_member_role := case when v_room.host_id = v_user_id then 'host' else 'listener' end;

  insert into public.room_members (room_id, user_id, role)
  values (v_room.id, v_user_id, v_member_role);

  return jsonb_build_object('success', true, 'room_id', v_room.id, 'role', v_member_role);
end;
$$;

revoke all on function public.join_room(text) from public;
grant execute on function public.join_room(text) to authenticated, service_role;
