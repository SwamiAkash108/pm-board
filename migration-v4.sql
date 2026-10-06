-- v4 migration — custom per-project columns + people + assignees.
-- Idempotent: safe to run multiple times.

-- 1. columns: each project gets its own ordered set of stages
create table if not exists columns (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  name text not null,
  color text not null default '#8a7f6b',
  position float8 not null default 0,
  created_at timestamptz not null default now(),
  unique (project_id, name)
);

-- 2. people: simple roster (no accounts)
create table if not exists people (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  color text not null default '#2b4361',
  created_at timestamptz not null default now()
);

-- 3. tasks: assignee + drop the fixed status list so any column name works
alter table tasks add column if not exists assignee_id uuid references people(id) on delete set null;
alter table tasks drop constraint if exists tasks_status_check;

-- 4. backfill: give every existing project the classic four stages
insert into columns (project_id, name, color, position)
select p.id, s.name, s.color, s.pos
from projects p
cross join (values
  ('To do',   '#8a7f6b', 1),
  ('Doing',   '#c9912f', 2),
  ('Blocked', '#b3352c', 3),
  ('Done',    '#6b7040', 4)
) as s(name, color, pos)
on conflict (project_id, name) do nothing;

-- 5. RLS + policies (drop first so re-runs don't error)
alter table columns enable row level security;
alter table people enable row level security;
drop policy if exists "owner all" on columns;
drop policy if exists "owner all" on people;
create policy "owner all" on columns for all to authenticated using (true) with check (true);
create policy "owner all" on people for all to authenticated using (true) with check (true);

-- 6. realtime (ignore "already a member" on re-runs)
do $$
begin
  begin
    alter publication supabase_realtime add table columns;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table people;
  exception when duplicate_object then null;
  end;
end $$;

-- 7. exec_sql helper: REMOVED 06/10/2026 (security hardening).
--    Arbitrary-SQL RPC revoked and dropped from the live DB; do not re-add.
