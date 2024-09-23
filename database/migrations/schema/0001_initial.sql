create extension pgcrypto;

create table community_site_layout (
    community_site_layout_id text primary key
);

insert into community_site_layout values ('default');

create table community (
    community_id uuid primary key default gen_random_uuid(),
    active boolean default true not null,
    created_at timestamptz default current_timestamp not null,
    description text not null,
    display_name text not null unique,
    header_logo_url text not null,
    host text not null unique,
    name text not null unique,
    title text not null,
    banners_urls text[],
    copyright_notice text,
    extra_links jsonb,
    facebook_url text,
    flickr_url text,
    footer_logo_url text,
    github_url text,
    homepage_url text,
    instagram_url text,
    linkedin_url text,
    photos_urls text[],
    slack_url text,
    twitter_url text,
    wechat_url text,
    youtube_url text,
    community_site_layout_id text not null references community_site_layout default 'default'
);

create index community_community_site_layout_id_idx on community (community_site_layout_id);

create table region (
    region_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    name text not null,
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
    active boolean default true not null,
    created_at timestamptz default current_timestamp not null,
    description text not null,
    name text not null,
    slug text not null,
    banners_urls text[],
    city text,
    country text,
    extra_links jsonb,
    facebook_url text,
    flickr_url text,
    github_url text,
    homepage_url text,
    icon_url text,
    instagram_url text,
    latitude double precision,
    linkedin_url text,
    longitude double precision,
    photos_urls text[],
    slack_url text,
    tags text[],
    twitter_url text,
    wechat_url text,
    youtube_url text,
    community_id uuid not null references community,
    group_site_layout_id text not null references group_site_layout default 'default',
    region_id uuid not null references region,
    unique (name, community_id),
    unique (slug, community_id)
);

create index group_community_id_idx on "group" (community_id);
create index group_region_id_idx on "group" (region_id);
create index group_group_site_layout_id_idx on "group" (group_site_layout_id);

create table event_kind (
    event_kind_id text primary key,
    display_name text not null unique
);

insert into event_kind values ('in-person', 'In Person');
insert into event_kind values ('virtual', 'Virtual');
insert into event_kind values ('hybrid', 'Hybrid');

create table event (
    event_id uuid primary key default gen_random_uuid(),
    cancelled boolean default false not null,
    created_at timestamptz default current_timestamp not null,
    description text not null,
    ends_at timestamptz not null,
    postponed boolean default false not null,
    published boolean default false not null,
    title text not null,
    slug text not null,
    starts_at timestamptz not null,
    address text,
    banner_url text,
    capacity int check (capacity > 0),
    city text,
    icon_url text,
    latitude double precision,
    longitude double precision,
    photos_urls text[],
    postal_code text,
    recording_url text,
    streaming_url text,
    tags text[],
    venue text,
    event_kind_id text not null references event_kind,
    group_id uuid not null references "group",
    unique (slug, group_id)
);

create index event_group_id_idx on event (group_id);
create index event_event_kind_id_idx on event (event_kind_id);

create table session_kind (
    session_kind_id text primary key,
    display_name text not null unique
);

insert into session_kind values ('in-person', 'In-Person');
insert into session_kind values ('virtual', 'Virtual');
insert into session_kind values ('hybrid', 'Hybrid');

create table session (
    session_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    description text not null,
    ends_at timestamptz not null,
    starts_at timestamptz not null,
    title text not null,
    location text,
    recording_url text,
    streaming_url text,
    event_id uuid not null references event,
    session_kind_id text not null references session_kind
);

create index session_event_id_idx on session (event_id);
create index session_session_kind_id_idx on session (session_kind_id);

create table "user" (
    user_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    email text not null unique,
    bio text,
    city text,
    company text,
    country text,
    facebook_url text,
    first_name text,
    interests text[],
    last_name text,
    linkedin_url text,
    photo_url text,
    timezone text,
    title text,
    twitter_url text,
    website_url text
);

create table group_organizer (
    group_id uuid not null references "group",
    user_id uuid not null references "user",
    created_at timestamptz default current_timestamp not null,
    primary key (group_id, user_id)
);

create index group_organizer_group_id_idx on group_organizer (group_id);
create index group_organizer_user_id_idx on group_organizer (user_id);

create table group_member (
    group_id uuid not null references "group",
    user_id uuid not null references "user",
    created_at timestamptz default current_timestamp not null,
    primary key (group_id, user_id)
);

create index group_member_group_id_idx on group_member (group_id);
create index group_member_user_id_idx on group_member (user_id);

create table group_sponsor (
    group_sponsor_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    level text not null,
    logo_url text not null,
    name text not null,
    website_url text,
    group_id uuid not null references "group"
);

create index group_sponsor_group_id_idx on group_sponsor (group_id);

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
    created_at timestamptz default current_timestamp not null,
    primary key (event_id, user_id)
);

create index event_attendee_event_id_idx on event_attendee (event_id);
create index event_attendee_user_id_idx on event_attendee (user_id);

create table event_sponsor (
    event_sponsor_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    level text not null,
    logo_url text not null,
    name text not null,
    website_url text,
    event_id uuid not null references event
);

create index event_sponsor_event_id_idx on event_sponsor (event_id);

create table session_speaker (
    session_id uuid not null references session,
    user_id uuid not null references "user",
    created_at timestamptz default current_timestamp not null,
    featured boolean default false not null,
    primary key (session_id, user_id)
);

create index session_speaker_session_id_idx on session_speaker (session_id);
create index session_speaker_user_id_idx on session_speaker (user_id);
