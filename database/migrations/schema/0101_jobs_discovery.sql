create table if not exists jobs_discovery_integration (
    user_id uuid primary key references "user"(user_id) on delete cascade,
    enabled boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists jobs_discovery_source (
    jobs_discovery_source_id uuid primary key default gen_random_uuid(),
    user_id uuid not null references "user"(user_id) on delete cascade,
    url text not null,
    enabled boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id, url)
);

create table if not exists jobs_discovery_run (
    jobs_discovery_run_id uuid primary key default gen_random_uuid(),
    user_id uuid not null references "user"(user_id) on delete cascade,
    started_at timestamptz not null default now(),
    completed_at timestamptz,
    status text not null check (status in ('running', 'succeeded', 'failed')),
    discovered_count integer not null default 0 check (discovered_count >= 0),
    created_count integer not null default 0 check (created_count >= 0),
    error_message text
);

create table if not exists jobs_discovery_item (
    jobs_discovery_item_id uuid primary key default gen_random_uuid(),
    user_id uuid not null references "user"(user_id) on delete cascade,
    source_url text not null,
    fingerprint text not null,
    job_id uuid references jobs_job(job_id) on delete set null,
    created_at timestamptz not null default now(),
    unique (user_id, fingerprint)
);

create index if not exists jobs_discovery_source_enabled_idx
    on jobs_discovery_source (user_id) where enabled;
create index if not exists jobs_discovery_run_user_started_idx
    on jobs_discovery_run (user_id, started_at desc);
