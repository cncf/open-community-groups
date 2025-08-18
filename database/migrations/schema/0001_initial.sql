create extension pgcrypto;
create extension postgis;

create or replace function i_array_to_string(text[], text)
returns text language sql immutable as $$select array_to_string($1, $2)$$;

create table community_site_layout (
    community_site_layout_id text primary key
);

insert into community_site_layout values ('default');

create table community (
    community_id uuid primary key default gen_random_uuid(),
    active boolean default true not null,
    created_at timestamptz default current_timestamp not null,
    description text not null check (description <> ''),
    display_name text not null unique check (display_name <> ''),
    header_logo_url text not null check (header_logo_url <> ''),
    host text not null unique check (host <> ''),
    name text not null unique check (name <> ''),
    theme jsonb not null,
    title text not null check (title <> ''),
    community_site_layout_id text not null references community_site_layout default 'default',

    ad_banner_link_url text check (ad_banner_link_url <> ''),
    ad_banner_url text check (ad_banner_url <> ''),
    copyright_notice text check (copyright_notice <> ''),
    extra_links jsonb,
    facebook_url text check (facebook_url <> ''),
    flickr_url text check (flickr_url <> ''),
    footer_logo_url text check (footer_logo_url <> ''),
    github_url text check (github_url <> ''),
    instagram_url text check (instagram_url <> ''),
    linkedin_url text check (linkedin_url <> ''),
    new_group_details text check (new_group_details <> ''),
    photos_urls text[],
    slack_url text check (slack_url <> ''),
    twitter_url text check (twitter_url <> ''),
    website_url text check (website_url <> ''),
    wechat_url text check (wechat_url <> ''),
    youtube_url text check (youtube_url <> '')
);

create index community_community_site_layout_id_idx on community (community_site_layout_id);

create table "user" (
    user_id uuid primary key default gen_random_uuid(),
    auth_hash bytea not null check (auth_hash <> ''),
    community_id uuid not null references community,
    created_at timestamptz default current_timestamp not null,
    email text not null unique check (email <> ''),
    email_verified boolean not null default false,
    name text not null check (name <> ''),
    username text not null check (username <> '') unique,

    bio text check (bio <> ''),
    city text check (city <> ''),
    company text check (company <> ''),
    country text check (country <> ''),
    facebook_url text check (facebook_url <> ''),
    interests text[],
    linkedin_url text check (linkedin_url <> ''),
    password text check (password <> ''),
    photo_url text check (photo_url <> ''),
    timezone text check (timezone <> ''),
    title text check (title <> ''),
    twitter_url text check (twitter_url <> ''),
    website_url text check (website_url <> '')
);

create index user_community_id_idx on "user" (community_id);

create table region (
    region_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    name text not null check (name <> ''),
    normalized_name text not null check (normalized_name <> '')
        generated always as (regexp_replace(lower(name), '[^\w]+', '-', 'g')) stored,
    "order" integer,
    community_id uuid not null references community,

    unique (name, community_id),
    unique (normalized_name, community_id)
);

create index region_community_id_idx on region (community_id);

create table group_category (
    group_category_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    name text not null check (name <> ''),
    normalized_name text not null check (normalized_name <> '')
        generated always as (regexp_replace(lower(name), '[^\w]+', '-', 'g')) stored,
    "order" integer,
    community_id uuid not null references community,

    unique (name, community_id),
    unique (normalized_name, community_id)
);

create index group_category_community_id_idx on group_category (community_id);

create table group_site_layout (
    group_site_layout_id text primary key
);

insert into group_site_layout values ('default');

create table "group" (
    group_id uuid primary key default gen_random_uuid(),
    active boolean default true not null,
    created_at timestamptz default current_timestamp not null,
    deleted boolean default false not null,
    name text not null check (name <> ''),
    slug text not null check (slug <> ''),
    tsdoc tsvector not null
        generated always as (
            setweight(to_tsvector('simple', name), 'A') ||
            setweight(to_tsvector('simple', slug), 'A') ||
            setweight(to_tsvector('simple', i_array_to_string(coalesce(tags, '{}'), ' ')), 'B') ||
            setweight(to_tsvector('simple', coalesce(city, '')), 'C') ||
            setweight(to_tsvector('simple', coalesce(state, '')), 'C') ||
            setweight(to_tsvector('simple', coalesce(country_name, '')), 'C')
        ) stored,
    community_id uuid not null references community,
    group_site_layout_id text not null references group_site_layout default 'default',
    group_category_id uuid not null references group_category,

    description text check (description <> ''),
    banner_url text,
    city text check (city <> ''),
    country_code text check (country_code <> ''),
    country_name text check (country_name <> ''),
    deleted_at timestamptz,

    extra_links jsonb,
    facebook_url text check (facebook_url <> ''),
    flickr_url text check (flickr_url <> ''),
    github_url text check (github_url <> ''),
    instagram_url text check (instagram_url <> ''),
    linkedin_url text check (linkedin_url <> ''),
    location geography(point, 4326),
    logo_url text check (logo_url <> ''),
    photos_urls text[],
    slack_url text check (slack_url <> ''),
    state text check (state <> ''),
    tags text[],
    twitter_url text check (twitter_url <> ''),
    website_url text check (website_url <> ''),
    wechat_url text check (wechat_url <> ''),
    youtube_url text check (youtube_url <> ''),
    region_id uuid references region,

    unique (slug, community_id),
    check ((deleted = false) or (deleted = true and active = false))
);

create index group_community_id_idx on "group" (community_id);
create index group_group_category_id_idx on "group" (group_category_id);
create index group_region_id_idx on "group" (region_id);
create index group_group_site_layout_id_idx on "group" (group_site_layout_id);
create index group_tsdoc_idx on "group" using gin (tsdoc);
create index group_location_idx on "group" using gist (location);

create table group_member (
    group_id uuid not null references "group",
    user_id uuid not null references "user",
    created_at timestamptz default current_timestamp not null,

    primary key (group_id, user_id)
);

create index group_member_group_id_idx on group_member (group_id);
create index group_member_user_id_idx on group_member (user_id);

create table group_team (
    group_id uuid not null references "group",
    user_id uuid not null references "user",
    role text not null check (role <> ''),
    created_at timestamptz default current_timestamp not null,

    "order" integer,

    primary key (group_id, user_id)
);

create index group_team_group_id_idx on group_team (group_id);
create index group_team_user_id_idx on group_team (user_id);

create table group_sponsor (
    group_sponsor_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    level text not null check (level <> ''),
    logo_url text not null check (logo_url <> ''),
    name text not null check (name <> ''),
    group_id uuid not null references "group",

    website_url text check (website_url <> '')
);

create index group_sponsor_group_id_idx on group_sponsor (group_id);

create table event_category (
    event_category_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    name text not null check (name <> ''),
    slug text not null check (slug <> ''),
    community_id uuid not null references community,

    "order" integer,

    unique (name, community_id),
    unique (slug, community_id)
);

create index event_category_community_id_idx on event_category (community_id);

create table event_kind (
    event_kind_id text primary key,
    display_name text not null unique
);

insert into event_kind values ('in-person', 'In Person');
insert into event_kind values ('virtual', 'Virtual');
insert into event_kind values ('hybrid', 'Hybrid');

create table event (
    event_id uuid primary key default gen_random_uuid(),
    canceled boolean default false not null,
    created_at timestamptz default current_timestamp not null,
    deleted boolean default false not null,
    description text not null check (description <> ''),
    name text not null check (name <> ''),
    published boolean default false not null,
    timezone text not null check (timezone <> ''),
    tsdoc tsvector not null
        generated always as (
            setweight(to_tsvector('simple', name), 'A') ||
            setweight(to_tsvector('simple', slug), 'A') ||
            setweight(to_tsvector('simple', i_array_to_string(coalesce(tags, '{}'), ' ')), 'B') ||
            setweight(to_tsvector('simple', coalesce(venue_name, '')), 'C') ||
            setweight(to_tsvector('simple', coalesce(venue_city, '')), 'C')
        ) stored,
    slug text not null check (slug <> ''),
    event_category_id uuid not null references event_category,
    event_kind_id text not null references event_kind,
    group_id uuid not null references "group",

    banner_url text check (banner_url <> ''),
    capacity int check (capacity >= 0),
    deleted_at timestamptz,
    description_short text check (description_short <> ''),
    ends_at timestamptz,
    logo_url text check (logo_url <> ''),
    meetup_url text check (meetup_url <> ''),
    photos_urls text[],
    published_at timestamptz,
    recording_url text check (recording_url <> ''),
    registration_required boolean,
    starts_at timestamptz,
    streaming_url text check (streaming_url <> ''),
    tags text[],
    timezone_abbr text check (timezone_abbr <> ''),
    venue_address text check (venue_address <> ''),
    venue_city text check (venue_city <> ''),
    venue_name text check (venue_name <> ''),
    venue_zip_code text check (venue_zip_code <> ''),
    published_by uuid references "user",

    unique (slug, group_id),
    check ((deleted = false) or (deleted = true and published = false))
);

create index event_group_id_idx on event (group_id);
create index event_event_category_id_idx on event (event_category_id);
create index event_event_kind_id_idx on event (event_kind_id);
create index event_published_by_idx on event (published_by);
create index event_tsdoc_idx on event using gin (tsdoc);

create table event_host (
    event_id uuid not null references event,
    user_id uuid not null references "user",
    created_at timestamptz default current_timestamp not null,

    primary key (event_id, user_id)
);

create index event_host_event_id_idx on event_host (event_id);
create index event_host_user_id_idx on event_host (user_id);

create table event_attendee (
    event_id uuid not null references event,
    user_id uuid not null references "user",
    checked_in boolean default false not null,
    created_at timestamptz default current_timestamp not null,

    primary key (event_id, user_id)
);

create index event_attendee_event_id_idx on event_attendee (event_id);
create index event_attendee_user_id_idx on event_attendee (user_id);

create table event_sponsor (
    event_sponsor_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    level text not null check (level <> ''),
    logo_url text not null check (logo_url <> ''),
    name text not null check (name <> ''),
    event_id uuid not null references event,

    website_url text check (website_url <> '')
);

create index event_sponsor_event_id_idx on event_sponsor (event_id);

create table session_kind (
    session_kind_id text primary key,
    display_name text not null unique
);

insert into session_kind values ('in-person', 'In-Person');
insert into session_kind values ('virtual', 'Virtual');

create table session (
    session_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    description text not null check (description <> ''),
    ends_at timestamptz not null,
    name text not null,
    starts_at timestamptz not null,
    event_id uuid not null references event,
    session_kind_id text not null references session_kind,

    location text check (location <> ''),
    recording_url text check (recording_url <> ''),
    streaming_url text check (streaming_url <> '')
);

create index session_event_id_idx on session (event_id);
create index session_session_kind_id_idx on session (session_kind_id);

create table session_speaker (
    session_id uuid not null references session,
    user_id uuid not null references "user",
    created_at timestamptz default current_timestamp not null,
    featured boolean default false not null,

    primary key (session_id, user_id)
);

create index session_speaker_session_id_idx on session_speaker (session_id);
create index session_speaker_user_id_idx on session_speaker (user_id);

create table auth_session (
    session_id text primary key,

    data jsonb not null,
    expires_at timestamptz not null
);

create table email_verification_code (
    email_verification_code_id uuid primary key default gen_random_uuid(),
    user_id uuid not null unique references "user" on delete cascade,

    created_at timestamptz default current_timestamp not null
);

create index email_verification_code_user_id_idx on email_verification_code (user_id);
