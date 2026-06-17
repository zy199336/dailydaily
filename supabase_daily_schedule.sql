create table if not exists public.daily_schedule_tasks (
  id uuid primary key,
  title text not null,
  description text,
  start_date date not null,
  end_date date not null,
  start_time time,
  end_time time,
  is_all_day boolean not null default false,
  is_completed boolean not null default false,
  owner_id text not null default 'default',
  user_id uuid references auth.users(id) on delete set null,
  recurrence_rule text not null default 'none',
  priority integer not null default 0,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint daily_schedule_tasks_date_order check (end_date >= start_date)
);

alter table public.daily_schedule_tasks
  add column if not exists user_id uuid references auth.users(id) on delete set null,
  add column if not exists recurrence_rule text not null default 'none',
  add column if not exists priority integer not null default 0;

create index if not exists daily_schedule_tasks_owner_updated_idx
  on public.daily_schedule_tasks (owner_id, updated_at);

create index if not exists daily_schedule_tasks_user_updated_idx
  on public.daily_schedule_tasks (user_id, updated_at);

create index if not exists daily_schedule_tasks_owner_priority_idx
  on public.daily_schedule_tasks (owner_id, start_date, priority);

create index if not exists daily_schedule_tasks_user_priority_idx
  on public.daily_schedule_tasks (user_id, start_date, priority);

create index if not exists daily_schedule_tasks_date_range_idx
  on public.daily_schedule_tasks (start_date, end_date);

alter table public.daily_schedule_tasks enable row level security;

grant select, insert, update on table public.daily_schedule_tasks to anon;
grant select, insert, update on table public.daily_schedule_tasks to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'daily_schedule_tasks'
      and policyname = 'daily_schedule_tasks_public_read'
  ) then
    create policy "daily_schedule_tasks_public_read"
      on public.daily_schedule_tasks
      for select
      using (true);
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'daily_schedule_tasks'
      and policyname = 'daily_schedule_tasks_public_insert'
  ) then
    create policy "daily_schedule_tasks_public_insert"
      on public.daily_schedule_tasks
      for insert
      with check (true);
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'daily_schedule_tasks'
      and policyname = 'daily_schedule_tasks_public_update'
  ) then
    create policy "daily_schedule_tasks_public_update"
      on public.daily_schedule_tasks
      for update
      using (true)
      with check (true);
  end if;
end
$$;

comment on table public.daily_schedule_tasks is
  'Dedicated table for the Daily Schedule app. Do not use for other projects.';
