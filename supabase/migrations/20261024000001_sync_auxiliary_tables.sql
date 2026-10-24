-- Migration: Auxiliary sync tables (history, most_played, search_history)
-- Created: 2026-10-24

create table if not exists public.history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  track_id text not null,
  title text not null,
  artist text not null,
  image_url text,
  duration text,
  file_path text,
  is_youtube boolean default false,
  played_at timestamptz default now()
);

alter table public.history enable row level security;

create policy "Users can view own history"
  on public.history for select
  using (auth.uid() = user_id);

create policy "Users can insert own history"
  on public.history for insert
  with check (auth.uid() = user_id);

create policy "Users can delete own history"
  on public.history for delete
  using (auth.uid() = user_id);

create index if not exists idx_history_user_played on public.history(user_id, played_at desc);

create table if not exists public.most_played (
  id text primary key default gen_random_uuid()::text,
  user_id uuid not null references auth.users(id) on delete cascade,
  track_id text not null,
  count integer not null default 1,
  updated_at timestamptz default now(),
  constraint uq_most_played unique(user_id, track_id)
);

alter table public.most_played enable row level security;

create policy "Users can view own most played"
  on public.most_played for select
  using (auth.uid() = user_id);

create policy "Users can upsert own most played"
  on public.most_played for insert
  with check (auth.uid() = user_id);

create policy "Users can update own most played"
  on public.most_played for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete own most played"
  on public.most_played for delete
  using (auth.uid() = user_id);

create table if not exists public.search_history (
  id text primary key default gen_random_uuid()::text,
  user_id uuid not null references auth.users(id) on delete cascade,
  query text not null,
  timestamp text,
  created_at timestamptz default now(),
  constraint uq_search_query unique(user_id, query)
);

alter table public.search_history enable row level security;

create policy "Users can view own search history"
  on public.search_history for select
  using (auth.uid() = user_id);

create policy "Users can insert own search history"
  on public.search_history for insert
  with check (auth.uid() = user_id);

create policy "Users can delete own search history"
  on public.search_history for delete
  using (auth.uid() = user_id);
