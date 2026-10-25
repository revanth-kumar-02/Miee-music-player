-- Migration: Add room_messages table for live in-room chat and song suggestions

create table if not exists public.room_messages (
  id text primary key default gen_random_uuid()::text,
  room_id text not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  user_name text,
  user_avatar text,
  content text not null,
  type text not null default 'text' check (type in ('text', 'song_suggestion')),
  track_id text,
  track_title text,
  track_artist text,
  track_image_url text,
  is_youtube boolean default true,
  created_at timestamptz default now()
);

alter table public.room_messages enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies where tablename = 'room_messages' and policyname = 'Room members can view room messages'
  ) then
    create policy "Room members can view room messages"
      on public.room_messages for select
      using (
        auth.uid() is not null
        and (
          exists (
            select 1 from public.rooms r
            where r.id = public.room_messages.room_id and r.host_id = auth.uid()
          )
          or exists (
            select 1 from public.room_members rm
            where rm.room_id = public.room_messages.room_id and rm.user_id = auth.uid()
          )
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies where tablename = 'room_messages' and policyname = 'Room members can insert messages'
  ) then
    create policy "Room members can insert messages"
      on public.room_messages for insert
      with check (
        auth.uid() is not null
        and auth.uid() = user_id
        and (
          exists (
            select 1 from public.rooms r
            where r.id = room_id and r.host_id = auth.uid()
          )
          or exists (
            select 1 from public.room_members rm
            where rm.room_id = room_id and rm.user_id = auth.uid()
          )
        )
      );
  end if;
end $$;

alter publication supabase_realtime add table public.room_messages;
