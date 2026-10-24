-- Migration: 20261024000002_update_join_room_error.sql
-- Description: Update join_room RPC function to enforce exact "Room is full" message and safe non-throwing auth check

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
$$ language plpgsql security definer;
