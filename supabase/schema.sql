-- Living Building: sign-in, roles and shared data for the self-hosted version.
-- Run this once in Supabase: Dashboard > SQL Editor > New query > paste > Run.

-- 1. Which email domains may sign up, and the role each one starts with.
--    Replace the example with your university's real domain(s).
create table if not exists public.allowed_domains (
  domain text primary key,
  role   text not null default 'student' check (role in ('student','supervisor','dean'))
);
insert into public.allowed_domains (domain, role) values ('example.edu.iq', 'student')
  on conflict (domain) do nothing;

-- 2. One profile per signed-in person, holding their role.
create table if not exists public.profiles (
  id         uuid primary key references auth.users on delete cascade,
  email      text not null,
  role       text not null default 'student' check (role in ('student','supervisor','dean')),
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
drop policy if exists "read own profile" on public.profiles;
create policy "read own profile" on public.profiles for select to authenticated using (id = auth.uid());

-- New sign-ups: refuse emails outside the allowed domains, otherwise create the profile.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare d text := lower(split_part(new.email, '@', 2)); r text;
begin
  select role into r from public.allowed_domains where domain = d;
  if r is null then
    raise exception 'Email domain % is not allowed', d;
  end if;
  insert into public.profiles (id, email, role) values (new.id, lower(new.email), r);
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

-- 3. The shared data: ideas, reservations, approvals, and the dean's plan.
create table if not exists public.docs (
  coll       text not null check (coll in ('ideas','state','approvals','deanplan')),
  id         text not null,
  data       jsonb not null,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key (coll, id)
);
alter table public.docs enable row level security;

drop policy if exists "signed-in people read" on public.docs;
create policy "signed-in people read" on public.docs for select to authenticated using (true);

drop policy if exists "write by role" on public.docs;
create policy "write by role" on public.docs for insert to authenticated with check (
  coll in ('ideas','state')
  or (coll = 'approvals' and public.my_role() in ('supervisor','dean'))
  or (coll = 'deanplan'  and public.my_role() in ('supervisor','dean')));

drop policy if exists "update by role" on public.docs;
create policy "update by role" on public.docs for update to authenticated
  using (
    coll = 'state'
    or (coll = 'ideas' and (updated_by = auth.uid() or public.my_role() in ('supervisor','dean')))
    or (coll = 'approvals' and public.my_role() in ('supervisor','dean'))
    or (coll = 'deanplan'  and public.my_role() in ('supervisor','dean')))
  with check (
    coll in ('ideas','state')
    or (coll = 'approvals' and public.my_role() in ('supervisor','dean'))
    or (coll = 'deanplan'  and public.my_role() in ('supervisor','dean')));

drop policy if exists "staff delete" on public.docs;
create policy "staff delete" on public.docs for delete to authenticated
  using (public.my_role() in ('supervisor','dean'));

-- Reservations: a student may only reserve for themselves, and may not take
-- an idea someone else holds (unless that hold has expired and was never approved).
create or replace function public.docs_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  staff boolean := coalesce(public.my_role() in ('supervisor','dean'), false);
  me text := auth.uid()::text;
  nb text; ob text; oat bigint := 0; approved boolean := false;
  hold_ms bigint := 21::bigint * 86400000;
begin
  if new.coll = 'state' and not staff then
    nb := new.data->>'by';
    if tg_op = 'UPDATE' then
      ob := old.data->>'by';
      oat := coalesce((old.data->>'at')::bigint, 0);
      select exists (select 1 from public.docs a where a.coll = 'approvals' and a.id = new.id
                     and a.data->>'ok' = 'true' and a.data->>'by' = ob) into approved;
    end if;
    if nb is distinct from ob then
      if nb is not null and nb <> me then
        raise exception 'You can only reserve an idea for yourself';
      end if;
      if ob is not null and ob <> me
         and (approved or oat > (extract(epoch from now()) * 1000)::bigint - hold_ms) then
        raise exception 'This idea is reserved by someone else';
      end if;
    end if;
  end if;
  new.updated_by := auth.uid();
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists docs_guard on public.docs;
create trigger docs_guard before insert or update on public.docs
  for each row execute function public.docs_guard();

-- Live updates in the page.
do $$ begin
  alter publication supabase_realtime add table public.docs;
exception when duplicate_object then null; end $$;

-- 4. Making someone a supervisor or the dean (run after they have signed in once):
--   update public.profiles set role = 'supervisor' where email = 'name@your-university.edu.iq';
--   update public.profiles set role = 'dean'       where email = 'dean@your-university.edu.iq';
