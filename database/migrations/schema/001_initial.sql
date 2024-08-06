create extension pgcrypto;

create table community_site_layout (
    community_site_layout_id text primary key
);

insert into community_site_layout values ('default');

create table community (
    community_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    name text not null check (name <> '') unique,
    display_name text not null check (display_name <> '') unique,
    active boolean default true not null,
    introduction text check (introduction <> ''),
    photos_urls text[],
    header_logo_url text check (header_logo_url <> ''),
    footer_logo_url text check (footer_logo_url <> ''),
    facebook_url text check (facebook_url <> ''),
    flickr_url text check (flickr_url <> ''),
    github_url text check (github_url <> ''),
    homepage_url text check (homepage_url <> ''),
    instagram_url text check (instagram_url <> ''),
    linkedin_url text check (linkedin_url <> ''),
    slack_url text check (slack_url <> ''),
    twitter_url text check (twitter_url <> ''),
    wechat_url text check (wechat_url <> ''),
    youtube_url text check (youtube_url <> ''),
    copyright_notice text check (copyright_notice <> ''),
    extra_links jsonb,
    community_site_layout_id text not null references community_site_layout default 'default'
);

create index community_community_site_layout_id_idx on community (community_site_layout_id);

create table region (
    region_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    name text not null check (name <> ''),
    community_id uuid not null references community,
    unique (name, community_id)
);

create index region_community_id_idx on region (community_id);

create table group_site_layout (
    group_site_layout_id text primary key
);

insert into group_site_layout values ('default');

create table "group" (
    group_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    name text not null check (name <> ''),
    slug text not null check (slug <> ''),
    country text check (country <> ''),
    city text check (city <> ''),
    latitude double precision,
    longitude double precision,
    active boolean default true not null,
    introduction text check (introduction <> ''),
    photos_urls text[],
    facebook_url text check (facebook_url <> ''),
    flickr_url text check (flickr_url <> ''),
    github_url text check (github_url <> ''),
    homepage_url text check (homepage_url <> ''),
    instagram_url text check (instagram_url <> ''),
    linkedin_url text check (linkedin_url <> ''),
    slack_url text check (slack_url <> ''),
    twitter_url text check (twitter_url <> ''),
    wechat_url text check (wechat_url <> ''),
    youtube_url text check (youtube_url <> ''),
    extra_links jsonb,
    community_id uuid not null references community,
    group_site_layout_id text not null references group_site_layout default 'default',
    region_id uuid not null references region,
    unique (name, community_id),
    unique (slug, community_id)
);

create index group_community_id_idx on "group" (community_id);
create index group_group_site_layout_id_idx on "group" (group_site_layout_id);
create index group_region_id_idx on "group" (region_id);

create table event (
    event_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    name text not null check (name <> ''),
    slug text not null check (name <> '') unique,
    title text not null check (title <> ''),
    description text check (description <> ''),
    latitude double precision,
    longitude double precision,
    group_id uuid not null references "group",
    unique (name, group_id),
    unique (slug, group_id)
);

create index event_group_id_idx on event (group_id);

create table "user" (
    user_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    email text not null check (email <> '') unique,
    first_name text check (first_name <> ''),
    last_name text check (last_name <> ''),
    photo_url text check (photo_url <> '')
);

create table organizer (
    user_id uuid not null references "user",
    group_id uuid not null references "group",
    joined_at timestamptz default current_timestamp not null,
    primary key (user_id, group_id)
);

create index organizer_user_id_idx on organizer (user_id);
create index organizer_group_id_idx on organizer (group_id);

create table member (
    user_id uuid not null references "user",
    group_id uuid not null references "group",
    joined_at timestamptz default current_timestamp not null,
    primary key (user_id, group_id)
);

create index member_user_id_idx on member (user_id);
create index member_group_id_idx on member (group_id);

create table attendee (
    user_id uuid not null references "user",
    event_id uuid not null references event,
    registered_at timestamptz default current_timestamp not null,
    primary key (user_id, event_id)
);

create index attendee_user_id_idx on attendee (user_id);
create index attendee_event_id_idx on attendee (event_id);
