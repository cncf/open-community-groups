create table if not exists group_event_integration (
    group_id uuid primary key references "group"(group_id) on delete cascade,
    created_by_user_id uuid not null references "user"(user_id),
    enabled boolean not null default false,
    city text not null default 'Baku',
    timezone text not null default 'Asia/Baku',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists group_event_integration_source (
    group_event_integration_source_id uuid primary key default gen_random_uuid(),
    group_id uuid not null references "group"(group_id) on delete cascade,
    url text not null,
    enabled boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (group_id, url)
);

create table if not exists group_event_integration_run (
    group_event_integration_run_id uuid primary key default gen_random_uuid(),
    group_id uuid not null references "group"(group_id) on delete cascade,
    started_at timestamptz not null default now(),
    completed_at timestamptz,
    status text not null check (status in ('running', 'succeeded', 'failed')),
    discovered_count integer not null default 0 check (discovered_count >= 0),
    created_count integer not null default 0 check (created_count >= 0),
    error_message text
);

create table if not exists group_event_integration_item (
    group_event_integration_item_id uuid primary key default gen_random_uuid(),
    group_id uuid not null references "group"(group_id) on delete cascade,
    source_url text not null,
    fingerprint text not null,
    event_id uuid references event(event_id) on delete set null,
    created_at timestamptz not null default now(),
    unique (group_id, fingerprint)
);

create index if not exists group_event_integration_source_enabled_idx
    on group_event_integration_source (group_id)
    where enabled;
create index if not exists group_event_integration_run_group_started_idx
    on group_event_integration_run (group_id, started_at desc);

create table if not exists partner_integration (
    partner_integration_id uuid primary key default gen_random_uuid(),
    alliance_id uuid not null references alliance(alliance_id) on delete cascade,
    name text not null,
    logo_url text,
    website_url text,
    attribution_copy text not null default '',
    public boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (alliance_id, name)
);
