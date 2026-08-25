-- RunCanvas Supabase 스키마 (프로젝트 ref: kqakxyzssscoyppargws, ap-northeast-2)
-- 적용됨: 2026-08-25 migration "initial_schema". 변경은 새 migration으로.

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  weight_kg double precision,
  avatar_url text,
  created_at timestamptz not null default now()
);

create table public.runs (
  id uuid primary key,                           -- 클라이언트 SwiftData Run.id 그대로
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  distance_m double precision not null,
  moving_s integer not null,
  avg_hr double precision,
  max_hr double precision,
  calories double precision not null,
  route jsonb,                                   -- [{"lat":..,"lon":..,"t":..}]
  created_at timestamptz not null default now()
);
create index runs_user_started on public.runs (user_id, started_at desc);

create table public.user_badges (
  user_id uuid not null references auth.users(id) on delete cascade,
  badge text not null,
  earned_at timestamptz not null default now(),
  primary key (user_id, badge)
);

alter table public.profiles    enable row level security;
alter table public.runs        enable row level security;
alter table public.user_badges enable row level security;

create policy "own profile" on public.profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);
create policy "own runs" on public.runs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own badges" on public.user_badges
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true);
create policy "avatar read" on storage.objects
  for select using (bucket_id = 'avatars');
create policy "avatar write own folder" on storage.objects
  for insert with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "avatar update own folder" on storage.objects
  for update using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
