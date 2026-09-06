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

-- migration "delete_own_account" (2026-08-26): 본인 계정 삭제 RPC (App Store 5.1.1(v))
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  -- storage.objects는 직접 삭제 금지(storage.protect_delete 트리거) → 아바타는 클라이언트가 Storage API로 삭제
  delete from auth.users where id = uid;   -- profiles/runs/user_badges는 cascade
end;
$$;
revoke execute on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;
-- migration "delete_own_account_v2": 계정 삭제 시 앱이 본인 아바타를 지울 수 있도록
create policy "avatar delete own folder" on storage.objects
  for delete using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

-- migration "profiles_height_cm" (2026-08-26): 첫 로그인 시 키 입력
alter table public.profiles add column if not exists height_cm double precision;

-- migration "marathon_events" (2026-09-06): 마라톤·러닝 이벤트 일정 (공개 읽기 전용 데이터)
-- 앱에 JSON을 박아 두면 일정 하나 바꾸는 데 앱 심사가 필요해서 서버에 둔다.
-- scripts/sync_marathons.py 가 6시간마다 upsert 하고 지난 일정은 지운다(GitHub Actions).
create table public.marathon_events (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  name_en text,
  event_date date,                                  -- 날짜 미정이면 null
  region text,
  place text,
  courses text[] not null default '{}',             -- ["5km","Half","Full"] 등 원본 종목 문자열
  type text not null default '대회',                -- '대회' | '테마런'
  tags text[] not null default '{}',                -- 야간 / 기부·공익 / 펫 / 풀코스
  status text,                                      -- open | closed | scheduled
  reg_start_date date,
  reg_end_date date,
  fee_min integer,
  image_url text,
  signup_url text,
  source text,
  updated_at timestamptz not null default now()
);
-- 동기화 upsert 키. 날짜 미정(null)끼리도 같은 대회로 보도록 NULLS NOT DISTINCT
create unique index marathon_events_name_date on public.marathon_events (name, event_date) nulls not distinct;
create index marathon_events_date on public.marathon_events (event_date);

alter table public.marathon_events enable row level security;
-- 공개 일정이라 로그인 없이 읽는다. 쓰기는 service_role(동기화 스크립트)만.
create policy "마라톤 일정 읽기" on public.marathon_events
  for select using (true);

-- migration "courses" (2026-09-06): 사용자가 등록해 공유하는 러닝 코스
-- 기록 하나를 코스로 올리면 지역별로 누구나 받아서 "따라뛰기" 한다.
-- 경로 앞뒤는 클라이언트가 잘라서 올린다(집·직장이 그대로 드러나지 않게) — CourseGeometry.trimmed
create table public.courses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  owner_nickname text not null default '',        -- 목록에서 조인 없이 보여주려고 복사해 둔다
  name text not null,
  region text not null,                           -- '서울' 등 앱의 지역 칩과 같은 문자열
  distance_m double precision not null,
  path jsonb not null,                            -- [{"lat":..,"lon":..}]
  created_at timestamptz not null default now()
);
create index courses_region on public.courses (region, created_at desc);

alter table public.courses enable row level security;
-- 공유가 목적이라 읽기는 열고, 쓰기는 본인 것만
create policy "코스 읽기" on public.courses
  for select using (true);
create policy "본인 코스 등록" on public.courses
  for insert with check (auth.uid() = owner_id);
create policy "본인 코스 수정" on public.courses
  for update using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy "본인 코스 삭제" on public.courses
  for delete using (auth.uid() = owner_id);
