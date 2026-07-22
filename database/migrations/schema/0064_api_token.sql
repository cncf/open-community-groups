create table if not exists api_token (
    api_token_id uuid primary key default gen_random_uuid(),
    user_id uuid not null references "user" (user_id) on delete cascade,
    token_hash text not null unique,
    token_prefix text not null,
    name text,
    scopes text[] not null default array['read:public']::text[],
    created_at timestamptz not null default now(),
    last_used_at timestamptz,
    revoked_at timestamptz
);

create index if not exists api_token_user_id_idx
on api_token (user_id);

create index if not exists api_token_active_hash_idx
on api_token (token_hash)
where revoked_at is null;
