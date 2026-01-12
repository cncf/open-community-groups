-- =============================================================================
-- EXTENSIONS
-- =============================================================================
-- pgcrypto: Provides cryptographic functions, primarily for UUID generation
create extension if not exists pgcrypto;
-- PostGIS: Geographic extensions for location-based features.
create extension if not exists postgis;

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Helper function for full-text search: converts text array to space-separated
-- string for use in tsvector generation. Marked immutable for performance.
create or replace function i_array_to_string(text[], text)
returns text language sql immutable as $$select array_to_string($1, $2)$$;

-- Generates random alphanumeric codes for use as slugs.
create or replace function generate_slug(p_length int default 7)
returns text language sql as $$
    select string_agg(
        substr('23456789abcdefghjkmnpqrstuvwxyz', floor(random() * 31 + 1)::int, 1),
        ''
    )
    from generate_series(1, p_length)
$$;

-- =============================================================================
-- SITE TABLES
-- =============================================================================

-- Global site settings. There should only be one row in this table.
create table site (
    site_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    description text not null check (btrim(description) <> ''),
    theme jsonb not null,
    title text not null check (btrim(title) <> ''),

    copyright_notice text check (btrim(copyright_notice) <> ''),
    favicon_url text check (btrim(favicon_url) <> ''),
    footer_logo_url text check (btrim(footer_logo_url) <> ''),
    header_logo_url text check (btrim(header_logo_url) <> ''),
    og_image_url text check (btrim(og_image_url) <> '')
);

-- =============================================================================
-- COMMUNITY TABLES
-- =============================================================================

-- Site layout configurations for communities.
create table community_site_layout (
    community_site_layout_id text primary key
);

insert into community_site_layout values ('default');

-- Central community table - each community has its own groups and events.
create table community (
    community_id uuid primary key default gen_random_uuid(),
    active boolean default true not null,
    banner_url text not null check (btrim(banner_url) <> ''),
    community_site_layout_id text not null references community_site_layout default 'default',
    created_at timestamptz default current_timestamp not null,
    description text not null check (btrim(description) <> ''),
    display_name text not null unique check (btrim(display_name) <> ''),
    logo_url text not null check (btrim(logo_url) <> ''),
    name text not null unique check (btrim(name) <> ''),

    ad_banner_link_url text check (btrim(ad_banner_link_url) <> ''),
    ad_banner_url text check (btrim(ad_banner_url) <> ''),
    extra_links jsonb,
    facebook_url text check (btrim(facebook_url) <> ''),
    flickr_url text check (btrim(flickr_url) <> ''),
    github_url text check (btrim(github_url) <> ''),
    instagram_url text check (btrim(instagram_url) <> ''),
    linkedin_url text check (btrim(linkedin_url) <> ''),
    new_group_details text check (btrim(new_group_details) <> ''),
    og_image_url text check (btrim(og_image_url) <> ''),
    photos_urls text[],
    slack_url text check (btrim(slack_url) <> ''),
    twitter_url text check (btrim(twitter_url) <> ''),
    website_url text check (btrim(website_url) <> ''),
    wechat_url text check (btrim(wechat_url) <> ''),
    youtube_url text check (btrim(youtube_url) <> '')
);

create index community_community_site_layout_id_idx on community (community_site_layout_id);

-- =============================================================================
-- USER TABLES
-- =============================================================================

-- Users table. Authentication can be via password or external providers.
create table "user" (
    user_id uuid primary key default gen_random_uuid(),
    auth_hash text not null check (btrim(auth_hash) <> ''),
    created_at timestamptz default current_timestamp not null,
    email text not null unique check (btrim(email) <> ''),
    email_verified boolean not null default false,
    username text not null unique check (btrim(username) <> ''),

    bio text check (btrim(bio) <> ''),
    city text check (btrim(city) <> ''),
    company text check (btrim(company) <> ''),
    country text check (btrim(country) <> ''),
    facebook_url text check (btrim(facebook_url) <> ''),
    interests text[],
    legacy_id integer unique,
    linkedin_url text check (btrim(linkedin_url) <> ''),
    name text,
    password text check (btrim(password) <> ''),
    photo_url text check (btrim(photo_url) <> ''),
    timezone text check (btrim(timezone) <> ''),
    title text check (btrim(title) <> ''),
    twitter_url text check (btrim(twitter_url) <> ''),
    website_url text check (btrim(website_url) <> '')
);

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
    name text not null check (btrim(name) <> ''),
    normalized_name text not null check (btrim(normalized_name) <> '')
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
    name text not null check (btrim(name) <> ''),
    normalized_name text not null check (btrim(normalized_name) <> '')
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
    deleted boolean default false not null,
    group_category_id uuid not null references group_category,
    group_site_layout_id text not null references group_site_layout default 'default',
    name text not null check (btrim(name) <> ''),
    slug text not null check (btrim(slug) <> ''),
    tsdoc tsvector not null
        generated always as (
            setweight(to_tsvector('simple', name), 'A') ||
            setweight(to_tsvector('simple', i_array_to_string(coalesce(tags, '{}'), ' ')), 'B') ||
            setweight(to_tsvector('simple', coalesce(city, '')), 'C') ||
            setweight(to_tsvector('simple', coalesce(state, '')), 'C') ||
            setweight(to_tsvector('simple', coalesce(country_name, '')), 'C')
        ) stored,

    banner_url text check (btrim(banner_url) <> ''),
    city text check (btrim(city) <> ''),
    country_code text check (btrim(country_code) <> ''),
    country_name text check (btrim(country_name) <> ''),
    deleted_at timestamptz,
    description text check (btrim(description) <> ''),
    description_short text check (btrim(description_short) <> ''),
    extra_links jsonb,
    facebook_url text check (btrim(facebook_url) <> ''),
    flickr_url text check (btrim(flickr_url) <> ''),
    github_url text check (btrim(github_url) <> ''),
    instagram_url text check (btrim(instagram_url) <> ''),
    legacy_id integer unique,
    linkedin_url text check (btrim(linkedin_url) <> ''),
    location geography(point, 4326),
    logo_url text check (btrim(logo_url) <> ''),
    photos_urls text[],
    region_id uuid references region,
    slack_url text check (btrim(slack_url) <> ''),
    state text check (btrim(state) <> ''),
    tags text[],
    twitter_url text check (btrim(twitter_url) <> ''),
    website_url text check (btrim(website_url) <> ''),
    wechat_url text check (btrim(wechat_url) <> ''),
    youtube_url text check (btrim(youtube_url) <> ''),

    unique (slug, community_id),
    check ((deleted = false) or (deleted = true and active = false))
);

create index group_community_id_idx on "group" (community_id);
create index group_group_category_id_idx on "group" (group_category_id);
create index group_group_site_layout_id_idx on "group" (group_site_layout_id);
create index group_location_idx on "group" using gist (location);
create index group_region_id_idx on "group" (region_id);
create index group_search_idx on "group" (community_id, active)
    where active = true;
create index group_tsdoc_idx on "group" using gin (tsdoc);

-- Group membership tracking.
create table group_member (
    group_id uuid not null references "group",
    user_id uuid not null references "user",
    created_at timestamptz default current_timestamp not null,

    primary key (group_id, user_id)
);

create index group_member_group_id_idx on group_member (group_id);
create index group_member_user_id_idx on group_member (user_id);
create index group_member_group_id_created_at_idx on group_member (group_id, created_at);

-- Group roles.
create table group_role (
    group_role_id text primary key,
    display_name text not null unique check (btrim(display_name) <> '')
);

insert into group_role values ('organizer', 'Organizer');

-- Group managing team.
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

-- Sponsors supporting groups with different sponsorship levels.
create table group_sponsor (
    group_sponsor_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    group_id uuid not null references "group",
    logo_url text not null check (btrim(logo_url) <> ''),
    name text not null check (btrim(name) <> ''),

    website_url text check (btrim(website_url) <> '')
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
    name text not null check (btrim(name) <> ''),
    slug text not null check (btrim(slug) <> ''),

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

-- Meeting providers.
create table meeting_provider (
    meeting_provider_id text primary key,
    display_name text not null unique check (btrim(display_name) <> '')
);

insert into meeting_provider values ('zoom', 'Zoom');

-- Core events table.
create table event (
    event_id uuid primary key default gen_random_uuid(),
    canceled boolean default false not null,
    created_at timestamptz default current_timestamp not null,
    deleted boolean default false not null,
    description text not null check (btrim(description) <> ''),
    event_category_id uuid not null references event_category,
    event_kind_id text not null references event_kind,
    group_id uuid not null references "group",
    name text not null check (btrim(name) <> ''),
    published boolean not null default false,
    slug text not null check (btrim(slug) <> ''),
    timezone text not null check (btrim(timezone) <> ''),
    tsdoc tsvector not null
        generated always as (
            setweight(to_tsvector('simple', name), 'A') ||
            setweight(to_tsvector('simple', i_array_to_string(coalesce(tags, '{}'), ' ')), 'B') ||
            setweight(to_tsvector('simple', coalesce(venue_name, '')), 'C') ||
            setweight(to_tsvector('simple', coalesce(venue_city, '')), 'C')
        ) stored,

    banner_url text check (btrim(banner_url) <> ''),
    capacity int check (capacity >= 0),
    deleted_at timestamptz,
    description_short text check (btrim(description_short) <> ''),
    ends_at timestamptz,
    legacy_id integer unique,
    location geography(point, 4326),
    logo_url text check (btrim(logo_url) <> ''),
    meeting_error text check (btrim(meeting_error) <> ''),
    meeting_hosts text[],
    meeting_in_sync boolean,
    meeting_join_url text check (btrim(meeting_join_url) <> ''),
    meeting_provider_id text references meeting_provider,
    meeting_recording_url text check (btrim(meeting_recording_url) <> ''),
    meeting_requested boolean,
    meetup_url text check (btrim(meetup_url) <> ''),
    photos_urls text[],
    published_at timestamptz,
    published_by uuid references "user",
    registration_required boolean,
    starts_at timestamptz,
    tags text[],
    venue_address text check (btrim(venue_address) <> ''),
    venue_city text check (btrim(venue_city) <> ''),
    venue_country_code text check (btrim(venue_country_code) <> ''),
    venue_country_name text check (btrim(venue_country_name) <> ''),
    venue_name text check (btrim(venue_name) <> ''),
    venue_state text check (btrim(venue_state) <> ''),
    venue_zip_code text check (btrim(venue_zip_code) <> ''),

    unique (slug, group_id),
    check ((deleted = false) or (deleted = true and published = false)),
    check (not (published and canceled)),
    check (ends_at is null or (starts_at is not null and ends_at >= starts_at)),
    constraint event_meeting_conflict_chk check (
        not (
            meeting_requested = true
            and (meeting_join_url is not null or meeting_recording_url is not null)
        )
    ),
    constraint event_meeting_kind_chk check (
        not (
            meeting_requested = true
            and event_kind_id not in ('hybrid', 'virtual')
        )
    ),
    constraint event_meeting_capacity_required_chk check (
        not (meeting_requested = true and capacity is null)
    ),
    constraint event_meeting_provider_required_chk check (
        not (meeting_requested = true and meeting_provider_id is null)
    ),
    constraint event_meeting_requested_times_chk check (
        not (meeting_requested = true and (starts_at is null or ends_at is null))
    )
);

create index event_group_id_idx on event (group_id);
create index event_event_category_id_idx on event (event_category_id);
create index event_event_kind_id_idx on event (event_kind_id);
create index event_location_idx on event using gist (location);
create index event_meeting_sync_idx on event (meeting_requested, meeting_in_sync)
    where meeting_requested = true and meeting_in_sync = false;
create index event_published_by_idx on event (published_by);
create index event_search_idx on event (group_id, published, canceled, starts_at)
    where published = true and canceled = false;
create index event_starts_at_idx on event (starts_at)
    where published = true and canceled = false and deleted = false;
create index event_tsdoc_idx on event using gin (tsdoc);

-- Event hosts (who is running/presenting the event).
create table event_host (
    event_id uuid not null references event,
    user_id uuid not null references "user",
    created_at timestamptz default current_timestamp not null,

    primary key (event_id, user_id)
);

create index event_host_event_id_idx on event_host (event_id);
create index event_host_user_id_idx on event_host (user_id);

-- Event attendance tracking with check-in capability.
create table event_attendee (
    event_id uuid not null references event,
    user_id uuid not null references "user",
    checked_in boolean default false not null,
    created_at timestamptz default current_timestamp not null,

    checked_in_at timestamptz,

    primary key (event_id, user_id)
);

create index event_attendee_event_id_idx on event_attendee (event_id);
create index event_attendee_user_id_idx on event_attendee (user_id);
create index event_attendee_event_id_created_at_idx on event_attendee (event_id, created_at);

-- Group sponsors supporting events.
create table event_sponsor (
    created_at timestamptz default current_timestamp not null,
    event_id uuid not null references event,
    group_sponsor_id uuid not null references group_sponsor,
    level text not null check (btrim(level) <> ''),

    primary key (group_sponsor_id, event_id)
);

create index event_sponsor_event_id_idx on event_sponsor (event_id);
create index event_sponsor_group_sponsor_id_idx on event_sponsor (group_sponsor_id);

-- Event-level speakers.
create table event_speaker (
    created_at timestamptz default current_timestamp not null,
    event_id uuid not null references event,
    featured boolean default false not null,
    user_id uuid not null references "user",

    primary key (event_id, user_id)
);

create index event_speaker_event_id_idx on event_speaker (event_id);
create index event_speaker_user_id_idx on event_speaker (user_id);

-- =============================================================================
-- SESSION TABLES
-- =============================================================================

-- Session types.
create table session_kind (
    session_kind_id text primary key,
    display_name text not null unique
);

insert into session_kind values ('hybrid', 'Hybrid');
insert into session_kind values ('in-person', 'In-Person');
insert into session_kind values ('virtual', 'Virtual');

-- Sessions within events.
create table session (
    session_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    event_id uuid not null references event on delete cascade,
    name text not null check (btrim(name) <> ''),
    session_kind_id text not null references session_kind,
    starts_at timestamptz not null,

    description text check (btrim(description) <> ''),
    ends_at timestamptz,
    location text check (btrim(location) <> ''),
    meeting_error text check (btrim(meeting_error) <> ''),
    meeting_hosts text[],
    meeting_in_sync boolean,
    meeting_join_url text check (btrim(meeting_join_url) <> ''),
    meeting_provider_id text references meeting_provider,
    meeting_recording_url text check (btrim(meeting_recording_url) <> ''),
    meeting_requested boolean,

    check (ends_at is null or (starts_at is not null and ends_at >= starts_at)),
    constraint session_meeting_conflict_chk check (
        not (
            meeting_requested = true
            and (meeting_join_url is not null or meeting_recording_url is not null)
        )
    ),
    constraint session_meeting_provider_required_chk check (
        not (meeting_requested = true and meeting_provider_id is null)
    ),
    constraint session_meeting_requested_times_chk check (
        not (meeting_requested = true and (starts_at is null or ends_at is null))
    )
);

create index session_event_id_idx on session (event_id);
create index session_meeting_sync_idx on session (meeting_requested, meeting_in_sync)
    where meeting_requested = true and meeting_in_sync = false;
create index session_session_kind_id_idx on session (session_kind_id);

-- Session speakers.
create table session_speaker (
    created_at timestamptz default current_timestamp not null,
    featured boolean default false not null,
    session_id uuid not null references session on delete cascade,
    user_id uuid not null references "user",

    primary key (session_id, user_id)
);

create index session_speaker_session_id_idx on session_speaker (session_id);
create index session_speaker_user_id_idx on session_speaker (user_id);

-- =============================================================================
-- MEETING TABLES
-- =============================================================================

-- Meetings table (external provider meetings integration).
create table meeting (
    meeting_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    join_url text not null check (btrim(join_url) <> ''),
    meeting_provider_id text not null references meeting_provider,
    provider_meeting_id text not null check (btrim(provider_meeting_id) <> ''),

    event_id uuid references event on delete set null,
    password text,
    recording_url text check (btrim(recording_url) <> ''),
    session_id uuid references session on delete set null,
    updated_at timestamptz
);

create unique index meeting_event_id_idx on meeting (event_id);
create index meeting_meeting_provider_id_idx on meeting (meeting_provider_id);
create unique index meeting_meeting_provider_id_provider_meeting_id_idx on meeting (meeting_provider_id, provider_meeting_id);
create unique index meeting_session_id_idx on meeting (session_id);

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

    name text not null unique check (btrim(name) <> '')
);

insert into notification_kind (name) values ('community-team-invitation');
insert into notification_kind (name) values ('email-verification');
insert into notification_kind (name) values ('event-canceled');
insert into notification_kind (name) values ('event-custom');
insert into notification_kind (name) values ('event-published');
insert into notification_kind (name) values ('event-rescheduled');
insert into notification_kind (name) values ('event-welcome');
insert into notification_kind (name) values ('group-custom');
insert into notification_kind (name) values ('group-team-invitation');
insert into notification_kind (name) values ('group-welcome');
insert into notification_kind (name) values ('speaker-welcome');

-- Notification template data table for deduplicating template data across notifications.
-- Uses hash-based deduplication similar to the attachment table pattern.
create table notification_template_data (
    notification_template_data_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    data jsonb not null,
    hash text not null constraint notification_template_data_hash_idx unique
);

-- Queue for notifications to be sent.
create table notification (
    notification_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    kind text not null references notification_kind (name) on delete restrict,
    processed boolean not null default false,
    user_id uuid not null references "user" on delete cascade,

    error text check (btrim(error) <> ''),
    notification_template_data_id uuid references notification_template_data,
    processed_at timestamptz
);

create index notification_not_processed_idx on notification (notification_id) where processed = 'false';
create index notification_kind_idx on notification(kind);
create index notification_user_id_idx on notification(user_id);

-- Stores files that can be referenced by multiple notifications.
create table attachment (
    attachment_id uuid primary key default gen_random_uuid(),
    content_type text not null check (btrim(content_type) <> ''),
    created_at timestamptz default current_timestamp not null,
    data bytea not null,
    file_name text not null check (btrim(file_name) <> ''),
    hash text not null check (btrim(hash) <> '') constraint attachment_hash_idx unique
);

-- Junction table to link notifications to their attachments.
create table notification_attachment (
    notification_id uuid not null references notification(notification_id) on delete cascade,
    attachment_id uuid not null references attachment(attachment_id) on delete restrict,
    primary key (notification_id, attachment_id)
);

create index notification_attachment_attachment_id_idx on notification_attachment (attachment_id);

-- Custom notification tracking.
create table custom_notification (
    custom_notification_id uuid primary key default gen_random_uuid(),
    body text not null check (btrim(body) <> ''),
    created_at timestamptz default current_timestamp not null,
    subject text not null check (btrim(subject) <> ''),

    created_by uuid references "user" (user_id) on delete set null,
    event_id uuid references event (event_id) on delete cascade,
    group_id uuid references "group" (group_id) on delete cascade,

    check (
        (event_id is not null and group_id is null) or
        (event_id is null and group_id is not null)
    )
);

create index custom_notification_created_by_idx on custom_notification (created_by);
create index custom_notification_event_id_idx on custom_notification (event_id);
create index custom_notification_group_id_idx on custom_notification (group_id);

-- =============================================================================
-- IMAGE STORAGE TABLES
-- =============================================================================

-- Stores uploaded images when using the database storage provider.
create table images (
    file_name text primary key,
    content_type text not null,
    created_at timestamptz default current_timestamp not null,
    created_by uuid not null references "user",
    data bytea not null
);

-- =============================================================================
-- LEGACY TABLES
-- =============================================================================

-- Denormalized legacy event hosts. This table is populated externally and is
-- not used by event creation/update flows. It links directly to events.
create table legacy_event_host (
    legacy_event_host_id uuid primary key default gen_random_uuid(),
    event_id uuid not null references event,

    bio text check (btrim(bio) <> ''),
    name text check (btrim(name) <> ''),
    photo_url text check (btrim(photo_url) <> ''),
    title text check (btrim(title) <> '')
);

create index legacy_event_host_event_id_idx on legacy_event_host (event_id);

-- Denormalized legacy event speakers. This table is populated externally and
-- is not used by event creation/update flows. It links directly to events.
create table legacy_event_speaker (
    legacy_event_speaker_id uuid primary key default gen_random_uuid(),
    event_id uuid not null references event,

    bio text check (btrim(bio) <> ''),
    name text check (btrim(name) <> ''),
    photo_url text check (btrim(photo_url) <> ''),
    title text check (btrim(title) <> '')
);

create index legacy_event_speaker_event_id_idx on legacy_event_speaker (event_id);

-- =============================================================================
-- TRIGGER FUNCTIONS
-- =============================================================================

-- Trigger function to validate session timestamps within event bounds.
create or replace function check_session_within_event_bounds()
returns trigger as $$
declare
    v_event_ends_at timestamptz;
    v_event_starts_at timestamptz;
begin
    -- Get event bounds
    select starts_at, ends_at into v_event_starts_at, v_event_ends_at
    from event
    where event_id = NEW.event_id;

    -- Only validate if event has both bounds set
    if v_event_starts_at is not null and v_event_ends_at is not null then
        -- Session starts_at must be within event bounds
        if NEW.starts_at < v_event_starts_at or NEW.starts_at > v_event_ends_at then
            raise exception 'session starts_at must be within event bounds';
        end if;

        -- Session ends_at (if set) must be within event bounds
        if NEW.ends_at is not null and NEW.ends_at > v_event_ends_at then
            raise exception 'session ends_at must be within event bounds';
        end if;
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger function to validate event sponsor belongs to the event's group.
create or replace function check_event_sponsor_group()
returns trigger as $$
declare
    v_event_group_id uuid;
    v_sponsor_group_id uuid;
begin
    -- Get event's group
    select group_id into v_event_group_id
    from event
    where event_id = NEW.event_id;

    -- Get sponsor's group
    select group_id into v_sponsor_group_id
    from group_sponsor
    where group_sponsor_id = NEW.group_sponsor_id;

    -- Validate groups match
    if v_sponsor_group_id is distinct from v_event_group_id then
        raise exception 'sponsor not found in group';
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger function to validate event category belongs to the event's community.
create or replace function check_event_category_community()
returns trigger as $$
declare
    v_category_community_id uuid;
    v_group_community_id uuid;
begin
    -- Get event's group community
    select community_id into v_group_community_id
    from "group"
    where group_id = NEW.group_id;

    -- Get category's community
    select community_id into v_category_community_id
    from event_category
    where event_category_id = NEW.event_category_id;

    -- Validate communities match
    if v_category_community_id is distinct from v_group_community_id then
        raise exception 'event category not found in community';
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger function to validate group category belongs to the group's community.
create or replace function check_group_category_community()
returns trigger as $$
declare
    v_category_community_id uuid;
begin
    -- Get category's community
    select community_id into v_category_community_id
    from group_category
    where group_category_id = NEW.group_category_id;

    -- Validate communities match
    if v_category_community_id is distinct from NEW.community_id then
        raise exception 'group category not found in community';
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger function to validate region belongs to the group's community.
create or replace function check_group_region_community()
returns trigger as $$
declare
    v_region_community_id uuid;
begin
    -- Skip validation if region_id is null
    if NEW.region_id is null then
        return NEW;
    end if;

    -- Get region's community
    select community_id into v_region_community_id
    from region
    where region_id = NEW.region_id;

    -- Validate communities match
    if v_region_community_id is distinct from NEW.community_id then
        raise exception 'region not found in community';
    end if;

    return NEW;
end;
$$ language plpgsql;

-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- Trigger on session INSERT/UPDATE.
create trigger session_within_event_bounds_check
    before insert or update on session
    for each row
    execute function check_session_within_event_bounds();

-- Trigger on event_sponsor INSERT/UPDATE.
create trigger event_sponsor_group_check
    before insert or update on event_sponsor
    for each row
    execute function check_event_sponsor_group();

-- Trigger on event INSERT/UPDATE.
create trigger event_category_community_check
    before insert or update on event
    for each row
    execute function check_event_category_community();

-- Trigger on group INSERT/UPDATE.
create trigger group_category_community_check
    before insert or update on "group"
    for each row
    execute function check_group_category_community();

-- Trigger on group INSERT/UPDATE.
create trigger group_region_community_check
    before insert or update on "group"
    for each row
    execute function check_group_region_community();
