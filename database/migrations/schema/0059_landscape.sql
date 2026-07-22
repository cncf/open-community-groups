create table if not exists landscape_entry (
    landscape_entry_id uuid default gen_random_uuid() primary key,
    alliance_id uuid not null references alliance (alliance_id) on delete cascade,
    added_by_user_id uuid not null references "user" (user_id) on delete cascade,
    name text not null,
    slug text not null,
    kind text not null check (kind in ('startup', 'github_project', 'partner_community', 'podcast_lead', 'investor')),
    summary text not null,
    description text,
    website_url text,
    github_url text,
    logo_url text,
    category text,
    tags text[] default '{}'::text[] not null,
    published boolean default true not null,
    created_at timestamp with time zone default current_timestamp not null,
    updated_at timestamp with time zone,
    unique (alliance_id, slug)
);

create index if not exists landscape_entry_alliance_published_created_at_idx
on landscape_entry (alliance_id, published, created_at desc);

create index if not exists landscape_entry_published_created_at_idx
on landscape_entry (published, created_at desc);

create index if not exists landscape_entry_kind_idx
on landscape_entry (kind);

create index if not exists landscape_entry_tags_idx
on landscape_entry using gin (tags);
