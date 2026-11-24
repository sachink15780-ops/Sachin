-- Spark Sub Rewards database schema for Supabase
-- Run this in Supabase SQL Editor. This schema is an initial secure foundation.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  phone text,
  role text not null default 'user' check (role in ('user','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  channel_name text not null,
  channel_url text not null,
  channel_logo_url text,
  video_url text,
  video_title text,
  video_thumbnail_url text,
  reward numeric(10,2) not null default 10 check (reward > 0),
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  balance numeric(12,2) not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  task_id uuid not null references public.tasks(id),
  proof_image_path text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(user_id, task_id)
);

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('task_reward','withdrawal','adjustment')),
  amount numeric(12,2) not null,
  reference_id uuid,
  note text,
  created_at timestamptz not null default now()
);

create table if not exists public.withdrawals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount numeric(12,2) not null check (amount >= 100),
  upi_id text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected','paid')),
  admin_note text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.kyc_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'not_started' check (status in ('not_started','pending','verified','rejected')),
  step integer not null default 1 check (step between 1 and 3),
  details jsonb not null default '{}'::jsonb,
  admin_note text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id)
);

-- Automatically create a profile and empty wallet for a new auth user.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles(id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', new.email))
  on conflict (id) do nothing;
  insert into public.wallets(user_id, balance)
  values (new.id, 0)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'); $$;

alter table public.profiles enable row level security;
alter table public.tasks enable row level security;
alter table public.wallets enable row level security;
alter table public.submissions enable row level security;
alter table public.transactions enable row level security;
alter table public.withdrawals enable row level security;
alter table public.kyc_requests enable row level security;

-- Profiles: users can view/edit only their own profile; admin can view all.
drop policy if exists "profile select own or admin" on public.profiles;
create policy "profile select own or admin" on public.profiles for select using (id = auth.uid() or public.is_admin());
drop policy if exists "profile update own" on public.profiles;
create policy "profile update own" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- Tasks: active tasks visible to signed-in users; admins manage tasks.
drop policy if exists "active tasks visible" on public.tasks;
create policy "active tasks visible" on public.tasks for select using (is_active = true or public.is_admin());
drop policy if exists "admin task insert" on public.tasks;
create policy "admin task insert" on public.tasks for insert with check (public.is_admin());
drop policy if exists "admin task update" on public.tasks;
create policy "admin task update" on public.tasks for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin task delete" on public.tasks;
create policy "admin task delete" on public.tasks for delete using (public.is_admin());

-- Wallet: user reads own; only server/admin functions can mutate.
drop policy if exists "wallet read own or admin" on public.wallets;
create policy "wallet read own or admin" on public.wallets for select using (user_id = auth.uid() or public.is_admin());

-- Proofs: users can submit/read own; admin reviews.
drop policy if exists "submission read own or admin" on public.submissions;
create policy "submission read own or admin" on public.submissions for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists "submission create own" on public.submissions;
create policy "submission create own" on public.submissions for insert with check (user_id = auth.uid() and status = 'pending');
drop policy if exists "admin submission review" on public.submissions;
create policy "admin submission review" on public.submissions for update using (public.is_admin()) with check (public.is_admin());

-- Transaction history: read-only for user, full access for admin.
drop policy if exists "transactions read own or admin" on public.transactions;
create policy "transactions read own or admin" on public.transactions for select using (user_id = auth.uid() or public.is_admin());

-- Withdrawals: users submit/read own; admin manages statuses.
drop policy if exists "withdrawals read own or admin" on public.withdrawals;
create policy "withdrawals read own or admin" on public.withdrawals for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists "withdrawal request own" on public.withdrawals;
create policy "withdrawal request own" on public.withdrawals for insert with check (user_id = auth.uid() and status = 'pending' and amount >= 100);
drop policy if exists "admin withdrawal update" on public.withdrawals;
create policy "admin withdrawal update" on public.withdrawals for update using (public.is_admin()) with check (public.is_admin());

-- KYC: user can read/submit their own; admin review.
drop policy if exists "kyc read own or admin" on public.kyc_requests;
create policy "kyc read own or admin" on public.kyc_requests for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists "kyc create own" on public.kyc_requests;
create policy "kyc create own" on public.kyc_requests for insert with check (user_id = auth.uid());
drop policy if exists "kyc update own draft" on public.kyc_requests;
create policy "kyc update own draft" on public.kyc_requests for update using (user_id = auth.uid() and status in ('not_started','rejected')) with check (user_id = auth.uid() and status in ('not_started','pending','rejected'));
drop policy if exists "admin kyc review" on public.kyc_requests;
create policy "admin kyc review" on public.kyc_requests for update using (public.is_admin()) with check (public.is_admin());

-- Admin approval RPC credits the reward exactly once (submission status guard).
create or replace function public.review_submission(p_submission_id uuid, p_approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public
as $$
declare
  s public.submissions%rowtype;
  r numeric(10,2);
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  select * into s from public.submissions where id = p_submission_id for update;
  if not found then raise exception 'submission not found'; end if;
  if s.status <> 'pending' then raise exception 'submission already reviewed'; end if;

  if p_approve then
    select reward into r from public.tasks where id = s.task_id;
    update public.wallets set balance = balance + r, updated_at = now() where user_id = s.user_id;
    insert into public.transactions(user_id,kind,amount,reference_id,note)
      values(s.user_id,'task_reward',r,s.id,'Approved YouTube subscribe task');
    update public.submissions set status='approved',admin_note=p_note,reviewed_by=auth.uid(),reviewed_at=now() where id=s.id;
  else
    update public.submissions set status='rejected',admin_note=p_note,reviewed_by=auth.uid(),reviewed_at=now() where id=s.id;
  end if;
end;
$$;

-- Users may update only safe profile fields; role must be managed by trusted admin SQL.
drop policy if exists "profile update own" on public.profiles;
create policy "profile update own safe fields" on public.profiles
for update using (id = auth.uid()) with check (id = auth.uid());

-- Withdrawal RPC: checks balance and reserves requested amount.
create or replace function public.request_withdrawal(p_amount numeric, p_upi_id text)
returns uuid language plpgsql security definer set search_path = public
as $$
declare uid uuid := auth.uid(); bal numeric; wid uuid;
begin
 if uid is null then raise exception 'login required'; end if;
 if p_amount < 100 then raise exception 'minimum withdrawal is 100'; end if;
 if p_upi_id is null or length(trim(p_upi_id)) < 5 then raise exception 'invalid UPI ID'; end if;
 select balance into bal from public.wallets where user_id=uid for update;
 if bal is null or bal < p_amount then raise exception 'insufficient balance'; end if;
 update public.wallets set balance=balance-p_amount,updated_at=now() where user_id=uid;
 insert into public.withdrawals(user_id,amount,upi_id,status) values(uid,p_amount,trim(p_upi_id),'pending') returning id into wid;
 insert into public.transactions(user_id,kind,amount,reference_id,note) values(uid,'withdrawal',-p_amount,wid,'Withdrawal request reserved');
 return wid;
end; $$;

-- Storage bucket and private upload policies for screenshots.
insert into storage.buckets (id,name,public) values ('task-proofs','task-proofs',false)
on conflict (id) do update set public=false;
drop policy if exists "user uploads own proof files" on storage.objects;
create policy "user uploads own proof files" on storage.objects
for insert to authenticated with check (
 bucket_id='task-proofs' and (storage.foldername(name))[1]=auth.uid()::text
);
drop policy if exists "proof owner or admin can read" on storage.objects;
create policy "proof owner or admin can read" on storage.objects
for select to authenticated using (
 bucket_id='task-proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin())
);
-- Restrict profile update to non-privileged columns (role cannot be self-edited).
revoke update on public.profiles from authenticated;
grant update (display_name, phone) on public.profiles to authenticated;
