-- 一次性设置：在 Supabase 仪表盘 → SQL Editor 粘贴运行
-- One-time setup: paste & run in Supabase dashboard → SQL Editor

create table if not exists public.trip_checklist_2026 (
  key        text primary key,
  value      text,
  updated_at timestamptz default now()
);

alter table public.trip_checklist_2026 enable row level security;

create policy "family_read"  on public.trip_checklist_2026 for select using (true);
create policy "family_write" on public.trip_checklist_2026 for insert with check (true);
create policy "family_update" on public.trip_checklist_2026 for update using (true) with check (true);
