-- Required extensions for the Open Community Groups platform
-- pgcrypto: Provides cryptographic functions, primarily for UUID generation
-- PostGIS: Geographic extensions for location-based features
create extension pgcrypto;
create extension postgis;

-- Helper function for full-text search: converts text array to space-separated
-- string for use in tsvector generation. Marked immutable for performance.
create or replace function i_array_to_string(text[], text)
returns text language sql immutable as $$select array_to_string($1, $2)$$;

-- =============================================================================
-- COMMUNITY TABLES
-- =============================================================================

-- Site layout configurations for communities
create table community_site_layout (
    community_site_layout_id text primary key
);

insert into community_site_layout values ('default');

-- Central community table - each community is a separate tenant with its own
-- users, groups, and events. Multi-tenancy is implemented via host-based routing.
create table community (
    community_id uuid primary key default gen_random_uuid(),
    active boolean default true not null,
    community_site_layout_id text not null references community_site_layout default 'default',
    created_at timestamptz default current_timestamp not null,
    description text not null check (description <> ''),
    display_name text not null unique check (display_name <> ''),
    header_logo_url text not null check (header_logo_url <> ''),
    host text not null unique check (host <> ''), -- Used for multi-tenant routing
    name text not null unique check (name <> ''),
    theme jsonb not null,
    title text not null check (title <> ''),

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

-- =============================================================================
-- USER TABLES
-- =============================================================================

-- Users are scoped to communities (multi-tenant). Authentication can be via
-- password or external providers.
create table "user" (
    user_id uuid primary key default gen_random_uuid(),
    auth_hash text not null check (auth_hash <> ''),
    community_id uuid not null references community,
    created_at timestamptz default current_timestamp not null,
    email text not null check (email <> ''),
    email_verified boolean not null default false,
    username text not null check (username <> ''),

    bio text check (bio <> ''),
    city text check (city <> ''),
    company text check (company <> ''),
    country text check (country <> ''),
    facebook_url text check (facebook_url <> ''),
    interests text[],
    legacy_id integer unique,
    linkedin_url text check (linkedin_url <> ''),
    name text,
    password text check (password <> ''),
    photo_url text check (photo_url <> ''),
    timezone text check (timezone <> ''),
    title text check (title <> ''),
    twitter_url text check (twitter_url <> ''),
    website_url text check (website_url <> ''),

    unique (email, community_id),
    unique (username, community_id)
);

create index user_community_id_idx on "user" (community_id);
create index user_username_lower_idx on "user" (lower(username));
create index user_name_lower_idx on "user" (lower(name));
create index user_email_lower_idx on "user" (lower(email));

-- Community team members.
create table community_team (
    community_id uuid not null references community,
    accepted boolean default false not null,
    created_at timestamptz default current_timestamp not null,
    user_id uuid not null references "user",

    primary key (community_id, user_id)
);

create index community_team_community_id_idx on community_team (community_id);
create index community_team_user_id_idx on community_team (user_id);

-- =============================================================================
-- GROUP TABLES
-- =============================================================================

-- Regions provide geographic organization for groups within a community.
create table region (
    region_id uuid primary key default gen_random_uuid(),
    community_id uuid not null references community,
    created_at timestamptz default current_timestamp not null,
    name text not null check (name <> ''),
    normalized_name text not null check (normalized_name <> '')
        generated always as (regexp_replace(lower(name), '[^\w]+', '-', 'g')) stored,

    "order" integer,

    unique (name, community_id),
    unique (normalized_name, community_id)
);

create index region_community_id_idx on region (community_id);

-- Categories for organizing groups.
create table group_category (
    group_category_id uuid primary key default gen_random_uuid(),
    community_id uuid not null references community,
    created_at timestamptz default current_timestamp not null,
    name text not null check (name <> ''),
    normalized_name text not null check (normalized_name <> '')
        generated always as (regexp_replace(lower(name), '[^\w]+', '-', 'g')) stored,

    "order" integer,

    unique (name, community_id),
    unique (normalized_name, community_id)
);

create index group_category_community_id_idx on group_category (community_id);

-- Site layout configurations for groups.
create table group_site_layout (
    group_site_layout_id text primary key
);

insert into group_site_layout values ('default');

-- Core groups table.
create table "group" (
    group_id uuid primary key default gen_random_uuid(),
    active boolean default true not null,
    community_id uuid not null references community,
    created_at timestamptz default current_timestamp not null,
    deleted boolean default false not null, -- Soft deletion
    group_category_id uuid not null references group_category,
    group_site_layout_id text not null references group_site_layout default 'default',
    name text not null check (name <> ''),
    slug text not null check (slug <> ''),
    tsdoc tsvector not null -- Full-text search index with weighted fields
        generated always as (
            setweight(to_tsvector('simple', name), 'A') ||
            setweight(to_tsvector('simple', slug), 'A') ||
            setweight(to_tsvector('simple', i_array_to_string(coalesce(tags, '{}'), ' ')), 'B') ||
            setweight(to_tsvector('simple', coalesce(city, '')), 'C') ||
            setweight(to_tsvector('simple', coalesce(state, '')), 'C') ||
            setweight(to_tsvector('simple', coalesce(country_name, '')), 'C')
        ) stored,

    banner_url text,
    city text check (city <> ''),
    country_code text check (country_code <> ''),
    country_name text check (country_name <> ''),
    deleted_at timestamptz,
    description text check (description <> ''),
    description_short text check (description_short <> ''),
    extra_links jsonb,
    facebook_url text check (facebook_url <> ''),
    flickr_url text check (flickr_url <> ''),
    github_url text check (github_url <> ''),
    instagram_url text check (instagram_url <> ''),
    legacy_id integer unique,
    linkedin_url text check (linkedin_url <> ''),
    location geography(point, 4326), -- PostGIS geographic point
    logo_url text check (logo_url <> ''),
    photos_urls text[],
    region_id uuid references region,
    slack_url text check (slack_url <> ''),
    state text check (state <> ''),
    tags text[],
    twitter_url text check (twitter_url <> ''),
    website_url text check (website_url <> ''),
    wechat_url text check (wechat_url <> ''),
    youtube_url text check (youtube_url <> ''),

    unique (slug, community_id),
    check ((deleted = false) or (deleted = true and active = false)) -- Deleted groups must be inactive
);

create index group_community_id_idx on "group" (community_id);
create index group_group_category_id_idx on "group" (group_category_id);
create index group_group_site_layout_id_idx on "group" (group_site_layout_id);
create index group_location_idx on "group" using gist (location);
create index group_region_id_idx on "group" (region_id);
create index group_search_idx on "group" (community_id, active)
    where active = true;
create index group_tsdoc_idx on "group" using gin (tsdoc);

-- Group membership tracking
create table group_member (
    group_id uuid not null references "group",
    user_id uuid not null references "user",
    created_at timestamptz default current_timestamp not null,

    primary key (group_id, user_id)
);

create index group_member_group_id_idx on group_member (group_id);
create index group_member_user_id_idx on group_member (user_id);

-- Group roles
create table group_role (
    group_role_id text primary key,
    display_name text not null unique
);

insert into group_role values ('organizer', 'Organizer');

-- Group managing team
create table group_team (
    group_id uuid not null references "group",
    user_id uuid not null references "user",
    accepted boolean default false not null,
    created_at timestamptz default current_timestamp not null,
    role text not null references group_role,

    "order" integer,

    primary key (group_id, user_id)
);

create index group_team_group_id_idx on group_team (group_id);
create index group_team_user_id_idx on group_team (user_id);
create index group_team_role_idx on group_team (role);

-- Sponsors supporting groups with different sponsorship levels
create table group_sponsor (
    group_sponsor_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    group_id uuid not null references "group",
    logo_url text not null check (logo_url <> ''),
    name text not null check (name <> ''),

    website_url text check (website_url <> '')
);

create index group_sponsor_group_id_idx on group_sponsor (group_id);

-- =============================================================================
-- EVENT TABLES
-- =============================================================================

-- Categories for organizing events.
create table event_category (
    event_category_id uuid primary key default gen_random_uuid(),
    community_id uuid not null references community,
    created_at timestamptz default current_timestamp not null,
    name text not null check (name <> ''),
    slug text not null check (slug <> ''),

    "order" integer,

    unique (name, community_id),
    unique (slug, community_id)
);

create index event_category_community_id_idx on event_category (community_id);

-- Event types.
create table event_kind (
    event_kind_id text primary key,
    display_name text not null unique
);

insert into event_kind values ('in-person', 'In Person');
insert into event_kind values ('virtual', 'Virtual');
insert into event_kind values ('hybrid', 'Hybrid');

-- Core events table.
create table event (
    event_id uuid primary key default gen_random_uuid(),
    canceled boolean default false not null,
    created_at timestamptz default current_timestamp not null,
    deleted boolean default false not null, -- Soft deletion
    description text not null check (description <> ''),
    event_category_id uuid not null references event_category,
    event_kind_id text not null references event_kind,
    group_id uuid not null references "group",
    name text not null check (name <> ''),
    published boolean not null default false,
    slug text not null check (slug <> ''),
    timezone text not null check (timezone <> ''),
    tsdoc tsvector not null -- Full-text search index with weighted fields
        generated always as (
            setweight(to_tsvector('simple', name), 'A') ||
            setweight(to_tsvector('simple', slug), 'A') ||
            setweight(to_tsvector('simple', i_array_to_string(coalesce(tags, '{}'), ' ')), 'B') ||
            setweight(to_tsvector('simple', coalesce(venue_name, '')), 'C') ||
            setweight(to_tsvector('simple', coalesce(venue_city, '')), 'C')
        ) stored,

    banner_url text check (banner_url <> ''),
    capacity int check (capacity >= 0),
    deleted_at timestamptz,
    description_short text check (description_short <> ''),
    ends_at timestamptz,
    legacy_id integer unique,
    logo_url text check (logo_url <> ''),
    meetup_url text check (meetup_url <> ''),
    photos_urls text[],
    published_at timestamptz,
    published_by uuid references "user",
    recording_url text check (recording_url <> ''),
    registration_required boolean,
    starts_at timestamptz,
    streaming_url text check (streaming_url <> ''),
    tags text[],
    venue_address text check (venue_address <> ''),
    venue_city text check (venue_city <> ''),
    venue_name text check (venue_name <> ''),
    venue_zip_code text check (venue_zip_code <> ''),

    unique (slug, group_id),
    check ((deleted = false) or (deleted = true and published = false)), -- Deleted events can't be published
    check (not (published and canceled)) -- Published events can't be canceled
);

create index event_group_id_idx on event (group_id);
create index event_event_category_id_idx on event (event_category_id);
create index event_event_kind_id_idx on event (event_kind_id);
create index event_published_by_idx on event (published_by);
create index event_search_idx on event (group_id, published, canceled, starts_at)
    where published = true and canceled = false;
create index event_tsdoc_idx on event using gin (tsdoc);

-- Event hosts (who is running/presenting the event)
create table event_host (
    event_id uuid not null references event,
    user_id uuid not null references "user",
    created_at timestamptz default current_timestamp not null,

    primary key (event_id, user_id)
);

create index event_host_event_id_idx on event_host (event_id);
create index event_host_user_id_idx on event_host (user_id);

-- Event attendance tracking with check-in capability
create table event_attendee (
    event_id uuid not null references event,
    user_id uuid not null references "user",
    checked_in boolean default false not null,
    created_at timestamptz default current_timestamp not null,

    primary key (event_id, user_id)
);

create index event_attendee_event_id_idx on event_attendee (event_id);
create index event_attendee_user_id_idx on event_attendee (user_id);

-- Group sponsors supporting events
create table event_sponsor (
    created_at timestamptz default current_timestamp not null,
    event_id uuid not null references event,
    group_sponsor_id uuid not null references group_sponsor,
    level text not null check (level <> ''),

    primary key (group_sponsor_id, event_id)
);

create index event_sponsor_event_id_idx on event_sponsor (event_id);
create index event_sponsor_group_sponsor_id_idx on event_sponsor (group_sponsor_id);

-- =============================================================================
-- SESSION TABLES
-- =============================================================================

-- Session types.
create table session_kind (
    session_kind_id text primary key,
    display_name text not null unique
);

insert into session_kind values ('in-person', 'In-Person');
insert into session_kind values ('virtual', 'Virtual');

-- Sessions within events (for multi-track conferences, workshops with parts).
create table session (
    session_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    description text not null check (description <> ''),
    ends_at timestamptz not null,
    event_id uuid not null references event,
    name text not null,
    session_kind_id text not null references session_kind,
    starts_at timestamptz not null,

    location text check (location <> ''),
    recording_url text check (recording_url <> ''),
    streaming_url text check (streaming_url <> '')
);

create index session_event_id_idx on session (event_id);
create index session_session_kind_id_idx on session (session_kind_id);

-- Session speakers.
create table session_speaker (
    created_at timestamptz default current_timestamp not null,
    featured boolean default false not null,
    session_id uuid not null references session,
    user_id uuid not null references "user",

    primary key (session_id, user_id)
);

create index session_speaker_session_id_idx on session_speaker (session_id);
create index session_speaker_user_id_idx on session_speaker (user_id);

-- =============================================================================
-- AUTHENTICATION TABLES
-- =============================================================================

-- User session storage.
create table auth_session (
    auth_session_id text primary key,
    data jsonb not null,
    expires_at timestamptz not null
);

-- Email verification tokens for new user registration.
create table email_verification_code (
    email_verification_code_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    user_id uuid not null unique references "user" on delete cascade
);

create index email_verification_code_user_id_idx on email_verification_code (user_id);

-- =============================================================================
-- NOTIFICATION TABLES
-- =============================================================================

create table notification_kind (
    notification_kind_id uuid primary key default gen_random_uuid(),

    name text not null unique check (name <> '')
);

insert into notification_kind (name) values ('community-team-invitation');
insert into notification_kind (name) values ('email-verification');
insert into notification_kind (name) values ('event-canceled');
insert into notification_kind (name) values ('event-published');
insert into notification_kind (name) values ('event-rescheduled');
insert into notification_kind (name) values ('group-team-invitation');
insert into notification_kind (name) values ('group-welcome');

-- Queue for notifications to be sent.
create table notification (
    notification_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    kind text not null references notification_kind (name) on delete restrict,
    processed boolean not null default false, -- Processing status
    user_id uuid not null references "user" on delete cascade,

    error text check (error <> ''),
    processed_at timestamptz,
    template_data jsonb
);

create index notification_not_processed_idx on notification (notification_id) where processed = 'false';
create index notification_kind_idx on notification(kind);
create index notification_user_id_idx on notification(user_id);

-- =============================================================================
-- LEGACY TABLES
-- =============================================================================

-- Denormalized legacy event hosts. This table is populated externally and is
-- not used by event creation/update flows. It links directly to events.
create table legacy_event_host (
    legacy_event_host_id uuid primary key default gen_random_uuid(),
    event_id uuid not null references event,

    bio text check (bio <> ''),
    name text check (name <> ''),
    photo_url text check (photo_url <> ''),
    title text check (title <> '')
);

create index legacy_event_host_event_id_idx on legacy_event_host (event_id);

-- Denormalized legacy event speakers. This table is populated externally and
-- is not used by event creation/update flows. It links directly to events.
create table legacy_event_speaker (
    legacy_event_speaker_id uuid primary key default gen_random_uuid(),
    event_id uuid not null references event,

    bio text check (bio <> ''),
    name text check (name <> ''),
    photo_url text check (photo_url <> ''),
    title text check (title <> '')
);

create index legacy_event_speaker_event_id_idx on legacy_event_speaker (event_id);
