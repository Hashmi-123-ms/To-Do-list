-- Daybook Tasks — database setup for Supabase
-- Paste this whole file into Supabase → SQL Editor → New query → Run.

-- 1. Tasks table: one row per task, owned by the signed-in user
create table if not exists public.tasks (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title        text not null check (char_length(title) between 1 and 140),
  notes        text not null default '',
  due_date     date,                                  -- Task Date (deadline)
  done         boolean not null default false,        -- Complete / Pending
  completed_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists tasks_user_status_due_idx
  on public.tasks (user_id, done, due_date);

-- 2. Keep updated_at and completed_at correct automatically
create or replace function public.tasks_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if new.done and (tg_op = 'INSERT' or not old.done) then
    new.completed_at := now();
  elsif not new.done then
    new.completed_at := null;
  end if;
  return new;
end $$;

drop trigger if exists tasks_touch on public.tasks;
create trigger tasks_touch
  before insert or update on public.tasks
  for each row execute function public.tasks_touch();

-- 3. Row Level Security: each user can only see and change their own tasks
alter table public.tasks enable row level security;

drop policy if exists "Read own tasks"   on public.tasks;
drop policy if exists "Add own tasks"    on public.tasks;
drop policy if exists "Edit own tasks"   on public.tasks;
drop policy if exists "Delete own tasks" on public.tasks;

create policy "Read own tasks"   on public.tasks for select to authenticated using (auth.uid() = user_id);
create policy "Add own tasks"    on public.tasks for insert to authenticated with check (auth.uid() = user_id);
create policy "Edit own tasks"   on public.tasks for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Delete own tasks" on public.tasks for delete to authenticated using (auth.uid() = user_id);

-- 4. Handy view for the "Pending Tasks" feature (respects the same security)
create or replace view public.pending_tasks
  with (security_invoker = true) as
  select * from public.tasks where done = false order by due_date nulls last;
