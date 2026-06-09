-- FairFuel Phase 2 — Supabase Schema
-- Run this in the Supabase SQL editor for project pbhxyxmwdpbksgnrgzwr.
-- Safe to re-run: uses IF NOT EXISTS / OR REPLACE throughout.

-- ─────────────────────────────────────────────
-- TABLES
-- ─────────────────────────────────────────────

create table if not exists public.profiles (
    id           uuid primary key references auth.users on delete cascade,
    display_name text not null default '',
    created_at   timestamptz not null default now()
);

create table if not exists public.vehicles (
    id                               uuid primary key default gen_random_uuid(),
    name                             text not null,
    beacon_uuid                      text not null,
    fuel_efficiency_liters_per_100km float8 not null default 9.4,
    year                             int,
    make                             text,
    model                            text,
    created_at                       timestamptz not null default now()
);

create table if not exists public.memberships (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references public.profiles on delete cascade,
    vehicle_id uuid not null references public.vehicles on delete cascade,
    role       text not null check (role in ('owner', 'member')),
    created_at timestamptz not null default now(),
    unique (user_id, vehicle_id)
);

create table if not exists public.trips (
    id                      uuid primary key default gen_random_uuid(),
    vehicle_id              uuid not null references public.vehicles on delete cascade,
    driver_id               uuid references public.profiles on delete set null,
    driver_name             text not null default '',
    start_time              timestamptz not null,
    end_time                timestamptz not null,
    distance_km             float8 not null default 0,
    idle_seconds            float8 not null default 0,
    aggressive_accel_events int not null default 0,
    hard_brake_events       int not null default 0,
    estimated_fuel_liters   float8 not null default 0,
    is_manual               boolean not null default false,
    created_at              timestamptz not null default now()
);

create table if not exists public.fuel_entries (
    id         uuid primary key default gen_random_uuid(),
    vehicle_id uuid not null references public.vehicles on delete cascade,
    logged_by  uuid references public.profiles on delete set null,
    date       timestamptz not null,
    liters     float8 not null,
    total_cost float8 not null,
    odometer   float8,
    is_settled boolean not null default false,
    created_at timestamptz not null default now()
);

create table if not exists public.invites (
    id         uuid primary key default gen_random_uuid(),
    vehicle_id uuid not null references public.vehicles on delete cascade,
    created_by uuid not null references public.profiles on delete cascade,
    code       text not null unique,
    expires_at timestamptz not null,
    used_by    uuid references public.profiles on delete set null,
    used_at    timestamptz,
    created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────
-- ROW LEVEL SECURITY
-- ─────────────────────────────────────────────

alter table public.profiles    enable row level security;
alter table public.vehicles    enable row level security;
alter table public.memberships enable row level security;
alter table public.trips       enable row level security;
alter table public.fuel_entries enable row level security;
alter table public.invites     enable row level security;

-- profiles: user can read/insert/update own row
drop policy if exists "profiles_select_own"  on public.profiles;
drop policy if exists "profiles_insert_own"  on public.profiles;
drop policy if exists "profiles_update_own"  on public.profiles;

create policy "profiles_select_own"
    on public.profiles for select
    using (auth.uid() = id);

create policy "profiles_insert_own"
    on public.profiles for insert
    with check (auth.uid() = id);

create policy "profiles_update_own"
    on public.profiles for update
    using (auth.uid() = id)
    with check (auth.uid() = id);

-- vehicles: members can select; any auth user can insert; owner can update/delete
drop policy if exists "vehicles_select_member" on public.vehicles;
drop policy if exists "vehicles_insert_auth"   on public.vehicles;
drop policy if exists "vehicles_update_owner"  on public.vehicles;
drop policy if exists "vehicles_delete_owner"  on public.vehicles;

create policy "vehicles_select_member"
    on public.vehicles for select
    using (
        exists (
            select 1 from public.memberships
            where memberships.vehicle_id = vehicles.id
              and memberships.user_id = auth.uid()
        )
    );

create policy "vehicles_insert_auth"
    on public.vehicles for insert
    with check (auth.uid() is not null);

create policy "vehicles_update_owner"
    on public.vehicles for update
    using (
        exists (
            select 1 from public.memberships
            where memberships.vehicle_id = vehicles.id
              and memberships.user_id = auth.uid()
              and memberships.role = 'owner'
        )
    );

create policy "vehicles_delete_owner"
    on public.vehicles for delete
    using (
        exists (
            select 1 from public.memberships
            where memberships.vehicle_id = vehicles.id
              and memberships.user_id = auth.uid()
              and memberships.role = 'owner'
        )
    );

-- memberships: user can select own; user can insert own; owner or self can delete
drop policy if exists "memberships_select_own"        on public.memberships;
drop policy if exists "memberships_insert_own"        on public.memberships;
drop policy if exists "memberships_delete_owner_self" on public.memberships;

create policy "memberships_select_own"
    on public.memberships for select
    using (user_id = auth.uid());

create policy "memberships_insert_own"
    on public.memberships for insert
    with check (user_id = auth.uid());

create policy "memberships_delete_owner_self"
    on public.memberships for delete
    using (
        user_id = auth.uid()
        or exists (
            select 1 from public.memberships m2
            where m2.vehicle_id = memberships.vehicle_id
              and m2.user_id = auth.uid()
              and m2.role = 'owner'
        )
    );

-- trips: member of vehicle can select/insert (insert requires driver_id = auth.uid()); driver can update own
drop policy if exists "trips_select_member" on public.trips;
drop policy if exists "trips_insert_member" on public.trips;
drop policy if exists "trips_update_driver" on public.trips;

create policy "trips_select_member"
    on public.trips for select
    using (
        exists (
            select 1 from public.memberships
            where memberships.vehicle_id = trips.vehicle_id
              and memberships.user_id = auth.uid()
        )
    );

create policy "trips_insert_member"
    on public.trips for insert
    with check (
        driver_id = auth.uid()
        and exists (
            select 1 from public.memberships
            where memberships.vehicle_id = trips.vehicle_id
              and memberships.user_id = auth.uid()
        )
    );

create policy "trips_update_driver"
    on public.trips for update
    using (driver_id = auth.uid());

-- fuel_entries: member can select/insert (insert requires logged_by = auth.uid()); logger can update own
drop policy if exists "fuel_entries_select_member" on public.fuel_entries;
drop policy if exists "fuel_entries_insert_member" on public.fuel_entries;
drop policy if exists "fuel_entries_update_logger" on public.fuel_entries;

create policy "fuel_entries_select_member"
    on public.fuel_entries for select
    using (
        exists (
            select 1 from public.memberships
            where memberships.vehicle_id = fuel_entries.vehicle_id
              and memberships.user_id = auth.uid()
        )
    );

create policy "fuel_entries_insert_member"
    on public.fuel_entries for insert
    with check (
        logged_by = auth.uid()
        and exists (
            select 1 from public.memberships
            where memberships.vehicle_id = fuel_entries.vehicle_id
              and memberships.user_id = auth.uid()
        )
    );

create policy "fuel_entries_update_logger"
    on public.fuel_entries for update
    using (logged_by = auth.uid());

-- invites: owner can insert/select for their vehicles; any auth user can select unexpired unused invites
drop policy if exists "invites_select_owner"       on public.invites;
drop policy if exists "invites_select_redeem"      on public.invites;
drop policy if exists "invites_insert_owner"       on public.invites;

create policy "invites_select_owner"
    on public.invites for select
    using (
        exists (
            select 1 from public.memberships
            where memberships.vehicle_id = invites.vehicle_id
              and memberships.user_id = auth.uid()
              and memberships.role = 'owner'
        )
    );

create policy "invites_select_redeem"
    on public.invites for select
    using (
        auth.uid() is not null
        and used_at is null
        and expires_at > now()
    );

create policy "invites_insert_owner"
    on public.invites for insert
    with check (
        created_by = auth.uid()
        and exists (
            select 1 from public.memberships
            where memberships.vehicle_id = invites.vehicle_id
              and memberships.user_id = auth.uid()
              and memberships.role = 'owner'
        )
    );

-- ─────────────────────────────────────────────
-- RPC: redeem_invite
-- security definer bypasses RLS so the function can:
--   1. look up the invite by code
--   2. verify preconditions
--   3. insert the membership row
--   4. mark the invite used
-- ─────────────────────────────────────────────

create or replace function public.redeem_invite(invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_invite   public.invites%rowtype;
    v_vehicle  public.vehicles%rowtype;
begin
    -- Look up invite
    select * into v_invite
    from public.invites
    where code = invite_code;

    if not found then
        return jsonb_build_object('success', false, 'error', 'Code not found.');
    end if;

    -- Validate: not expired
    if v_invite.expires_at <= now() then
        return jsonb_build_object('success', false, 'error', 'Code has expired.');
    end if;

    -- Validate: not already used
    if v_invite.used_at is not null then
        return jsonb_build_object('success', false, 'error', 'Code has already been used.');
    end if;

    -- Validate: caller not already a member
    if exists (
        select 1 from public.memberships
        where vehicle_id = v_invite.vehicle_id
          and user_id = auth.uid()
    ) then
        return jsonb_build_object('success', false, 'error', 'You are already a member of this vehicle.');
    end if;

    -- Look up vehicle name for return value
    select * into v_vehicle from public.vehicles where id = v_invite.vehicle_id;

    -- Insert membership
    insert into public.memberships (user_id, vehicle_id, role)
    values (auth.uid(), v_invite.vehicle_id, 'member');

    -- Mark invite used
    update public.invites
    set used_by = auth.uid(),
        used_at = now()
    where id = v_invite.id;

    return jsonb_build_object(
        'success', true,
        'vehicle_id', v_invite.vehicle_id::text,
        'vehicle_name', v_vehicle.name
    );
end;
$$;

-- ─────────────────────────────────────────────
-- REALTIME
-- ─────────────────────────────────────────────

-- Enable Postgres Changes realtime publication for trips table.
-- This allows clients to subscribe via WebSocket to row-level change events.
alter publication supabase_realtime add table public.trips;
