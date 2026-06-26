-- Fresh baseline schema for GOUP Alliance deployments.
-- This migration is intended for empty databases only.
-- Function definitions are loaded separately from database/migrations/functions.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE FUNCTION public.check_event_attendee_waitlist() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    -- Serialize writes for the same event-user pair across both attendance tables
    perform pg_advisory_xact_lock(hashtext(NEW.event_id::text), hashtext(NEW.user_id::text));

    if exists (
        select 1
        from event_waitlist
        where event_id = NEW.event_id
        and user_id = NEW.user_id
    ) then
        raise exception 'user is already on the waiting list for this event';
    end if;

    return NEW;
end;
$$;

CREATE FUNCTION public.check_event_category_alliance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    v_category_alliance_id uuid;
    v_group_alliance_id uuid;
begin
    -- Get event's group alliance
    select alliance_id into v_group_alliance_id
    from "group"
    where group_id = NEW.group_id;

    -- Get category's alliance
    select alliance_id into v_category_alliance_id
    from event_category
    where event_category_id = NEW.event_category_id;

    -- Validate alliances match
    if v_category_alliance_id is distinct from v_group_alliance_id then
        raise exception 'event category not found in alliance';
    end if;

    return NEW;
end;
$$;

CREATE FUNCTION public.check_event_sponsor_group() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;

CREATE FUNCTION public.check_event_ticketing_consistency() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    v_event_id uuid;
    v_has_discount_codes boolean;
    v_has_ticket_types boolean;
    v_payment_currency_code text;
begin
    -- Resolve the affected event regardless of which table fired the trigger
    if tg_table_name = 'event' then
        v_event_id := coalesce(new.event_id, old.event_id);
    elsif tg_table_name = 'event_discount_code' then
        v_event_id := coalesce(new.event_id, old.event_id);
    elsif tg_table_name = 'event_ticket_type' then
        v_event_id := coalesce(new.event_id, old.event_id);
    else
        raise exception 'unsupported event ticketing consistency trigger table: %', tg_table_name;
    end if;

    if v_event_id is null then
        return null;
    end if;

    -- Skip rows whose parent event no longer exists
    select
        exists(
            select 1
            from event_discount_code
            where event_id = e.event_id
        ),
        exists(
            select 1
            from event_ticket_type
            where event_id = e.event_id
        ),
        e.payment_currency_code
    into
        v_has_discount_codes,
        v_has_ticket_types,
        v_payment_currency_code
    from event e
    where e.event_id = v_event_id;

    if not found then
        return null;
    end if;

    -- Enforce the persisted ticketing shape for each event
    if v_has_ticket_types and v_payment_currency_code is null then
        raise exception 'ticketed events require payment_currency_code';
    end if;

    if not v_has_ticket_types and v_has_discount_codes then
        raise exception 'discount_codes require ticket_types';
    end if;

    if not v_has_ticket_types and v_payment_currency_code is not null then
        raise exception 'payment_currency_code requires ticket_types';
    end if;

    return null;
end;
$$;

CREATE FUNCTION public.check_event_waitlist_attendee() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    -- Serialize writes for the same event-user pair across both attendance tables
    perform pg_advisory_xact_lock(hashtext(NEW.event_id::text), hashtext(NEW.user_id::text));

    if exists (
        select 1
        from event_attendee
        where event_id = NEW.event_id
        and user_id = NEW.user_id
    ) then
        raise exception 'user is already attending this event';
    end if;

    return NEW;
end;
$$;

CREATE FUNCTION public.check_group_category_alliance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    v_category_alliance_id uuid;
begin
    -- Get category's alliance
    select alliance_id into v_category_alliance_id
    from group_category
    where group_category_id = NEW.group_category_id;

    -- Validate alliances match
    if v_category_alliance_id is distinct from NEW.alliance_id then
        raise exception 'group category not found in alliance';
    end if;

    return NEW;
end;
$$;

CREATE FUNCTION public.check_group_region_alliance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    v_region_alliance_id uuid;
begin
    -- Skip validation if region_id is null
    if NEW.region_id is null then
        return NEW;
    end if;

    -- Get region's alliance
    select alliance_id into v_region_alliance_id
    from region
    where region_id = NEW.region_id;

    -- Validate alliances match
    if v_region_alliance_id is distinct from NEW.alliance_id then
        raise exception 'region not found in alliance';
    end if;

    return NEW;
end;
$$;

CREATE FUNCTION public.check_session_cfs_submission_approved() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    v_event_id uuid;
    v_status_id text;
begin
    -- Skip validation when no submission is linked
    if NEW.cfs_submission_id is null then
        return NEW;
    end if;

    -- Fetch submission event and status
    select cs.event_id, cs.status_id
    into v_event_id, v_status_id
    from cfs_submission cs
    where cs.cfs_submission_id = NEW.cfs_submission_id;

    -- Ensure submission exists
    if v_event_id is null then
        raise exception 'cfs submission not found';
    end if;

    -- Ensure submission belongs to the same event
    if v_event_id <> NEW.event_id then
        raise exception 'cfs submission does not belong to the session event';
    end if;

    -- Ensure submission is approved
    if v_status_id <> 'approved' then
        raise exception 'cfs submission must be approved';
    end if;

    -- Return validated row
    return NEW;
end;
$$;

CREATE FUNCTION public.check_session_within_event_bounds() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;

CREATE FUNCTION public.generate_slug(p_length integer DEFAULT 7) RETURNS text
    LANGUAGE sql
    AS $$
    select string_agg(
        substr('23456789abcdefghjkmnpqrstuvwxyz', floor(random() * 31 + 1)::int, 1),
        ''
    )
    from generate_series(1, p_length)
$$;

CREATE FUNCTION public.i_array_to_string(text[], text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$select array_to_string($1, $2)$_$;

CREATE FUNCTION public.validate_group_slug_pretty() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
begin
    if exists (
        select 1
        from "group" g
        where g.alliance_id = new.alliance_id
        and g.group_id <> new.group_id
        and g.slug_pretty = new.slug
    ) then
        raise exception 'Pretty slug is already used by another group in this alliance';
    end if;

    if new.slug_pretty is null then
        return new;
    end if;

    if char_length(new.slug_pretty) > 50 then
        raise exception 'Pretty slug must be 50 characters or fewer';
    end if;

    if new.slug_pretty !~ '^[a-z0-9-]+$' then
        raise exception 'Pretty slug must use lowercase ASCII letters, numbers, and hyphens only';
    end if;

    if new.slug_pretty !~ '^[a-z0-9]'
       or new.slug_pretty !~ '[a-z0-9]$' then
        raise exception 'Pretty slug must start and end with a lowercase ASCII letter or number';
    end if;

    if new.slug_pretty like '%--%' then
        raise exception 'Pretty slug cannot contain consecutive hyphens';
    end if;

    if new.slug_pretty = new.slug then
        raise exception 'Pretty slug must be different from the generated slug';
    end if;

    if exists (
        select 1
        from "group" g
        where g.alliance_id = new.alliance_id
        and g.group_id <> new.group_id
        and (
            g.slug = new.slug_pretty
            or g.slug_pretty = new.slug_pretty
        )
    ) then
        raise exception 'Pretty slug is already used by another group in this alliance';
    end if;

    return new;
end;
$_$;

SET default_tablespace = '';

SET default_table_access_method = heap;

CREATE TABLE public.alliance (
    alliance_id uuid DEFAULT gen_random_uuid() NOT NULL,
    active boolean DEFAULT true NOT NULL,
    banner_url text NOT NULL,
    alliance_site_layout_id text DEFAULT 'default'::text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    description text NOT NULL,
    display_name text NOT NULL,
    logo_url text NOT NULL,
    name text NOT NULL,
    ad_banner_link_url text,
    ad_banner_url text,
    extra_links jsonb,
    facebook_url text,
    flickr_url text,
    github_url text,
    instagram_url text,
    linkedin_url text,
    new_group_details text,
    og_image_url text,
    photos_urls text[],
    slack_url text,
    twitter_url text,
    website_url text,
    wechat_url text,
    youtube_url text,
    banner_mobile_url text NOT NULL,
    bluesky_url text,
    group_team_management_restricted boolean DEFAULT false NOT NULL,
    CONSTRAINT alliance_ad_banner_link_url_check CHECK ((btrim(ad_banner_link_url) <> ''::text)),
    CONSTRAINT alliance_ad_banner_url_check CHECK ((btrim(ad_banner_url) <> ''::text)),
    CONSTRAINT alliance_banner_mobile_url_check CHECK ((btrim(banner_mobile_url) <> ''::text)),
    CONSTRAINT alliance_banner_url_check CHECK ((btrim(banner_url) <> ''::text)),
    CONSTRAINT alliance_bluesky_url_check CHECK ((btrim(bluesky_url) <> ''::text)),
    CONSTRAINT alliance_description_check CHECK ((btrim(description) <> ''::text)),
    CONSTRAINT alliance_display_name_check CHECK ((btrim(display_name) <> ''::text)),
    CONSTRAINT alliance_facebook_url_check CHECK ((btrim(facebook_url) <> ''::text)),
    CONSTRAINT alliance_flickr_url_check CHECK ((btrim(flickr_url) <> ''::text)),
    CONSTRAINT alliance_github_url_check CHECK ((btrim(github_url) <> ''::text)),
    CONSTRAINT alliance_instagram_url_check CHECK ((btrim(instagram_url) <> ''::text)),
    CONSTRAINT alliance_linkedin_url_check CHECK ((btrim(linkedin_url) <> ''::text)),
    CONSTRAINT alliance_logo_url_check CHECK ((btrim(logo_url) <> ''::text)),
    CONSTRAINT alliance_name_check CHECK ((btrim(name) <> ''::text)),
    CONSTRAINT alliance_new_group_details_check CHECK ((btrim(new_group_details) <> ''::text)),
    CONSTRAINT alliance_og_image_url_check CHECK ((btrim(og_image_url) <> ''::text)),
    CONSTRAINT alliance_slack_url_check CHECK ((btrim(slack_url) <> ''::text)),
    CONSTRAINT alliance_twitter_url_check CHECK ((btrim(twitter_url) <> ''::text)),
    CONSTRAINT alliance_website_url_check CHECK ((btrim(website_url) <> ''::text)),
    CONSTRAINT alliance_wechat_url_check CHECK ((btrim(wechat_url) <> ''::text)),
    CONSTRAINT alliance_youtube_url_check CHECK ((btrim(youtube_url) <> ''::text))
);

CREATE TABLE public.alliance_permission (
    alliance_permission_id text NOT NULL,
    display_name text NOT NULL,
    CONSTRAINT alliance_permission_display_name_check CHECK ((btrim(display_name) <> ''::text))
);

CREATE TABLE public.alliance_redirect_settings (
    alliance_id uuid NOT NULL,
    base_legacy_url text,
    CONSTRAINT alliance_redirect_settings_base_legacy_url_chk CHECK (((base_legacy_url IS NULL) OR (base_legacy_url ~ '^https?://[^[:space:]/?#]+/?$'::text)))
);

CREATE TABLE public.alliance_role (
    alliance_role_id text NOT NULL,
    display_name text NOT NULL,
    CONSTRAINT alliance_role_display_name_check CHECK ((btrim(display_name) <> ''::text))
);

CREATE TABLE public.alliance_role_alliance_permission (
    alliance_permission_id text NOT NULL,
    alliance_role_id text NOT NULL
);

CREATE TABLE public.alliance_role_group_permission (
    alliance_role_id text NOT NULL,
    group_permission_id text NOT NULL
);

CREATE TABLE public.alliance_site_layout (
    alliance_site_layout_id text NOT NULL
);

CREATE TABLE public.alliance_team (
    alliance_id uuid NOT NULL,
    accepted boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    user_id uuid NOT NULL,
    role text NOT NULL
);

CREATE TABLE public.alliance_views (
    alliance_id uuid,
    day date NOT NULL,
    total integer NOT NULL
);

CREATE TABLE public.attachment (
    attachment_id uuid DEFAULT gen_random_uuid() NOT NULL,
    content_type text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    data bytea NOT NULL,
    file_name text NOT NULL,
    hash text NOT NULL,
    CONSTRAINT attachment_content_type_check CHECK ((btrim(content_type) <> ''::text)),
    CONSTRAINT attachment_file_name_check CHECK ((btrim(file_name) <> ''::text)),
    CONSTRAINT attachment_hash_check CHECK ((btrim(hash) <> ''::text))
);

CREATE TABLE public.audit_log (
    audit_log_id uuid DEFAULT gen_random_uuid() NOT NULL,
    action text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    resource_id uuid NOT NULL,
    resource_type text NOT NULL,
    actor_user_id uuid,
    actor_username text,
    alliance_id uuid,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    event_id uuid,
    group_id uuid,
    CONSTRAINT audit_log_action_check CHECK ((btrim(action) <> ''::text)),
    CONSTRAINT audit_log_actor_username_check CHECK (((actor_username IS NULL) OR (btrim(actor_username) <> ''::text))),
    CONSTRAINT audit_log_details_check CHECK ((jsonb_typeof(details) = 'object'::text)),
    CONSTRAINT audit_log_resource_type_check CHECK ((btrim(resource_type) <> ''::text))
);

CREATE TABLE public.auth_session (
    auth_session_id text NOT NULL,
    data jsonb NOT NULL,
    expires_at timestamp with time zone NOT NULL
);

CREATE TABLE public.cfs_submission (
    cfs_submission_id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    event_id uuid NOT NULL,
    session_proposal_id uuid NOT NULL,
    status_id text NOT NULL,
    action_required_message text,
    reviewed_by uuid,
    updated_at timestamp with time zone,
    CONSTRAINT cfs_submission_action_required_message_check CHECK ((btrim(action_required_message) <> ''::text))
);

CREATE TABLE public.cfs_submission_label (
    cfs_submission_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    event_cfs_label_id uuid NOT NULL
);

CREATE TABLE public.cfs_submission_rating (
    cfs_submission_id uuid NOT NULL,
    reviewer_id uuid NOT NULL,
    stars smallint NOT NULL,
    comments text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone,
    CONSTRAINT cfs_submission_rating_comments_check CHECK ((btrim(comments) <> ''::text)),
    CONSTRAINT cfs_submission_rating_stars_check CHECK (((stars >= 1) AND (stars <= 5)))
);

CREATE TABLE public.cfs_submission_status (
    cfs_submission_status_id text NOT NULL,
    display_name text NOT NULL,
    CONSTRAINT cfs_submission_status_display_name_check CHECK ((btrim(display_name) <> ''::text))
);

CREATE TABLE public.custom_notification (
    custom_notification_id uuid DEFAULT gen_random_uuid() NOT NULL,
    body text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    subject text NOT NULL,
    created_by uuid,
    event_id uuid,
    group_id uuid,
    CONSTRAINT custom_notification_body_check CHECK ((btrim(body) <> ''::text)),
    CONSTRAINT custom_notification_check CHECK ((((event_id IS NOT NULL) AND (group_id IS NULL)) OR ((event_id IS NULL) AND (group_id IS NOT NULL)))),
    CONSTRAINT custom_notification_subject_check CHECK ((btrim(subject) <> ''::text))
);

CREATE TABLE public.email_verification_code (
    email_verification_code_id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    user_id uuid NOT NULL
);

CREATE TABLE public.event (
    event_id uuid DEFAULT gen_random_uuid() NOT NULL,
    canceled boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted boolean DEFAULT false NOT NULL,
    description text NOT NULL,
    event_category_id uuid NOT NULL,
    event_kind_id text NOT NULL,
    group_id uuid NOT NULL,
    name text NOT NULL,
    published boolean DEFAULT false NOT NULL,
    slug text NOT NULL,
    timezone text NOT NULL,
    tsdoc tsvector GENERATED ALWAYS AS ((((setweight(to_tsvector('simple'::regconfig, name), 'A'::"char") || setweight(to_tsvector('simple'::regconfig, public.i_array_to_string(COALESCE(tags, '{}'::text[]), ' '::text)), 'B'::"char")) || setweight(to_tsvector('simple'::regconfig, COALESCE(venue_name, ''::text)), 'C'::"char")) || setweight(to_tsvector('simple'::regconfig, COALESCE(venue_city, ''::text)), 'C'::"char"))) STORED NOT NULL,
    banner_url text,
    capacity integer,
    deleted_at timestamp with time zone,
    description_short text,
    ends_at timestamp with time zone,
    legacy_id integer,
    location public.geography(Point,4326),
    logo_url text,
    meeting_error text,
    meeting_hosts text[],
    meeting_in_sync boolean,
    meeting_join_url text,
    meeting_provider_id text,
    meeting_recording_url text,
    meeting_requested boolean,
    meetup_url text,
    photos_urls text[],
    published_at timestamp with time zone,
    published_by uuid,
    registration_required boolean,
    starts_at timestamp with time zone,
    tags text[],
    venue_address text,
    venue_city text,
    venue_country_code text,
    venue_country_name text,
    venue_name text,
    venue_state text,
    venue_zip_code text,
    banner_mobile_url text,
    cfs_description text,
    cfs_enabled boolean,
    cfs_ends_at timestamp with time zone,
    cfs_starts_at timestamp with time zone,
    legacy_url text,
    event_reminder_enabled boolean DEFAULT true NOT NULL,
    event_reminder_evaluated_for_starts_at timestamp with time zone,
    event_reminder_sent_at timestamp with time zone,
    waitlist_enabled boolean DEFAULT false NOT NULL,
    payment_currency_code text,
    event_series_id uuid,
    attendee_approval_required boolean DEFAULT false NOT NULL,
    created_by uuid,
    meeting_provider_host_user text,
    meeting_sync_claimed_at timestamp with time zone,
    meeting_join_instructions text,
    meeting_recording_requested boolean DEFAULT true NOT NULL,
    meeting_recording_published boolean DEFAULT false NOT NULL,
    luma_url text,
    test_event boolean DEFAULT false NOT NULL,
    registration_questions jsonb DEFAULT '[]'::jsonb NOT NULL,
    CONSTRAINT event_attendee_approval_waitlist_exclusive_chk CHECK ((NOT ((attendee_approval_required = true) AND (waitlist_enabled = true)))),
    CONSTRAINT event_banner_mobile_url_check CHECK ((btrim(banner_mobile_url) <> ''::text)),
    CONSTRAINT event_banner_url_check CHECK ((btrim(banner_url) <> ''::text)),
    CONSTRAINT event_capacity_check CHECK ((capacity >= 0)),
    CONSTRAINT event_cfs_description_check CHECK ((btrim(cfs_description) <> ''::text)),
    CONSTRAINT event_cfs_fields_chk CHECK ((((cfs_enabled IS TRUE) AND (cfs_description IS NOT NULL) AND (cfs_starts_at IS NOT NULL) AND (cfs_ends_at IS NOT NULL)) OR ((cfs_enabled IS NOT TRUE) AND (cfs_description IS NULL) AND (cfs_starts_at IS NULL) AND (cfs_ends_at IS NULL)))),
    CONSTRAINT event_cfs_window_chk CHECK (((cfs_enabled IS NOT TRUE) OR ((cfs_starts_at < cfs_ends_at) AND (starts_at IS NOT NULL) AND (cfs_starts_at < starts_at) AND (cfs_ends_at < starts_at)))),
    CONSTRAINT event_check CHECK (((deleted = false) OR ((deleted = true) AND (published = false)))),
    CONSTRAINT event_check2 CHECK (((ends_at IS NULL) OR ((starts_at IS NOT NULL) AND (ends_at >= starts_at)))),
    CONSTRAINT event_description_check CHECK ((btrim(description) <> ''::text)),
    CONSTRAINT event_description_short_check CHECK ((btrim(description_short) <> ''::text)),
    CONSTRAINT event_legacy_url_check CHECK ((btrim(legacy_url) <> ''::text)),
    CONSTRAINT event_logo_url_check CHECK ((btrim(logo_url) <> ''::text)),
    CONSTRAINT event_luma_url_check CHECK ((btrim(luma_url) <> ''::text)),
    CONSTRAINT event_meeting_capacity_required_chk CHECK ((NOT ((meeting_requested = true) AND (capacity IS NULL)))),
    CONSTRAINT event_meeting_conflict_chk CHECK ((NOT ((meeting_requested = true) AND ((meeting_join_instructions IS NOT NULL) OR (meeting_join_url IS NOT NULL))))),
    CONSTRAINT event_meeting_error_check CHECK ((btrim(meeting_error) <> ''::text)),
    CONSTRAINT event_meeting_join_instructions_check CHECK ((btrim(meeting_join_instructions) <> ''::text)),
    CONSTRAINT event_meeting_join_url_check CHECK ((btrim(meeting_join_url) <> ''::text)),
    CONSTRAINT event_meeting_kind_chk CHECK ((NOT ((meeting_requested = true) AND (event_kind_id <> ALL (ARRAY['hybrid'::text, 'virtual'::text]))))),
    CONSTRAINT event_meeting_provider_host_user_check CHECK ((btrim(meeting_provider_host_user) <> ''::text)),
    CONSTRAINT event_meeting_provider_required_chk CHECK ((NOT ((meeting_requested = true) AND (meeting_provider_id IS NULL)))),
    CONSTRAINT event_meeting_recording_url_check CHECK ((btrim(meeting_recording_url) <> ''::text)),
    CONSTRAINT event_meeting_requested_times_chk CHECK ((NOT ((meeting_requested = true) AND ((starts_at IS NULL) OR (ends_at IS NULL))))),
    CONSTRAINT event_meetup_url_check CHECK ((btrim(meetup_url) <> ''::text)),
    CONSTRAINT event_name_check CHECK ((btrim(name) <> ''::text)),
    CONSTRAINT event_payment_currency_code_check CHECK ((btrim(payment_currency_code) <> ''::text)),
    CONSTRAINT event_slug_check CHECK ((btrim(slug) <> ''::text)),
    CONSTRAINT event_timezone_check CHECK ((btrim(timezone) <> ''::text)),
    CONSTRAINT event_venue_address_check CHECK ((btrim(venue_address) <> ''::text)),
    CONSTRAINT event_venue_city_check CHECK ((btrim(venue_city) <> ''::text)),
    CONSTRAINT event_venue_country_code_check CHECK ((btrim(venue_country_code) <> ''::text)),
    CONSTRAINT event_venue_country_name_check CHECK ((btrim(venue_country_name) <> ''::text)),
    CONSTRAINT event_venue_name_check CHECK ((btrim(venue_name) <> ''::text)),
    CONSTRAINT event_venue_state_check CHECK ((btrim(venue_state) <> ''::text)),
    CONSTRAINT event_venue_zip_code_check CHECK ((btrim(venue_zip_code) <> ''::text)),
    CONSTRAINT event_waitlist_capacity_required_chk CHECK ((NOT ((waitlist_enabled = true) AND (capacity IS NULL))))
);

CREATE TABLE public.event_attendee (
    event_id uuid NOT NULL,
    user_id uuid NOT NULL,
    checked_in boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    checked_in_at timestamp with time zone,
    manually_invited boolean DEFAULT false NOT NULL,
    status text DEFAULT 'confirmed'::text NOT NULL,
    registration_answers jsonb,
    CONSTRAINT event_attendee_status_chk CHECK ((status = ANY (ARRAY['confirmed'::text, 'invitation-canceled'::text, 'invitation-pending'::text, 'invitation-rejected'::text, 'registration-questions-pending'::text])))
);

CREATE TABLE public.event_category (
    event_category_id uuid DEFAULT gen_random_uuid() NOT NULL,
    alliance_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    name text NOT NULL,
    "order" integer,
    slug text GENERATED ALWAYS AS (btrim(regexp_replace(lower(name), '[^\w]+'::text, '-'::text, 'g'::text), '-'::text)) STORED NOT NULL,
    CONSTRAINT event_category_name_check CHECK ((btrim(name) <> ''::text)),
    CONSTRAINT event_category_slug_check CHECK ((btrim(slug) <> ''::text))
);

CREATE TABLE public.event_cfs_label (
    color text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    event_id uuid NOT NULL,
    event_cfs_label_id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    CONSTRAINT event_cfs_label_name_check CHECK (((btrim(name) <> ''::text) AND (char_length(name) <= 80)))
);

CREATE TABLE public.event_discount_code (
    event_discount_code_id uuid NOT NULL,
    active boolean DEFAULT true NOT NULL,
    code text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    event_id uuid NOT NULL,
    kind text NOT NULL,
    title text NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    available integer,
    amount_minor bigint,
    ends_at timestamp with time zone,
    percentage integer,
    starts_at timestamp with time zone,
    total_available integer,
    available_override_active boolean DEFAULT false NOT NULL,
    CONSTRAINT event_discount_code_amount_minor_check CHECK (((amount_minor IS NULL) OR (amount_minor > 0))),
    CONSTRAINT event_discount_code_available_check CHECK (((available IS NULL) OR (available >= 0))),
    CONSTRAINT event_discount_code_code_check CHECK ((btrim(code) <> ''::text)),
    CONSTRAINT event_discount_code_kind_check CHECK ((kind = ANY (ARRAY['fixed_amount'::text, 'percentage'::text]))),
    CONSTRAINT event_discount_code_kind_value_chk CHECK ((((kind = 'fixed_amount'::text) AND (amount_minor IS NOT NULL) AND (percentage IS NULL)) OR ((kind = 'percentage'::text) AND (percentage IS NOT NULL) AND (amount_minor IS NULL)))),
    CONSTRAINT event_discount_code_percentage_check CHECK (((percentage IS NULL) OR ((percentage >= 1) AND (percentage <= 100)))),
    CONSTRAINT event_discount_code_title_check CHECK ((btrim(title) <> ''::text)),
    CONSTRAINT event_discount_code_total_available_check CHECK (((total_available IS NULL) OR (total_available >= 0))),
    CONSTRAINT event_discount_code_window_chk CHECK (((ends_at IS NULL) OR (starts_at IS NULL) OR (ends_at >= starts_at)))
);

CREATE TABLE public.event_host (
    event_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE public.event_invitation_request (
    event_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    reviewed_at timestamp with time zone,
    reviewed_by uuid,
    registration_answers jsonb,
    CONSTRAINT event_invitation_request_check CHECK ((((status = 'pending'::text) AND (reviewed_at IS NULL) AND (reviewed_by IS NULL)) OR ((status = ANY (ARRAY['accepted'::text, 'rejected'::text])) AND (reviewed_at IS NOT NULL) AND (reviewed_by IS NOT NULL)))),
    CONSTRAINT event_invitation_request_status_check CHECK ((status = ANY (ARRAY['accepted'::text, 'pending'::text, 'rejected'::text])))
);

CREATE TABLE public.event_kind (
    event_kind_id text NOT NULL,
    display_name text NOT NULL
);

CREATE TABLE public.event_organizer (
    event_id uuid NOT NULL,
    user_id uuid NOT NULL,
    "order" integer
);

CREATE TABLE public.event_purchase (
    event_purchase_id uuid DEFAULT gen_random_uuid() NOT NULL,
    amount_minor bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    currency_code text NOT NULL,
    discount_amount_minor bigint DEFAULT 0 NOT NULL,
    event_id uuid NOT NULL,
    event_ticket_type_id uuid NOT NULL,
    status text NOT NULL,
    ticket_title text NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    user_id uuid NOT NULL,
    completed_at timestamp with time zone,
    discount_code text,
    event_discount_code_id uuid,
    hold_expires_at timestamp with time zone,
    payment_provider_id text,
    provider_checkout_session_id text,
    provider_checkout_url text,
    provider_payment_reference text,
    refunded_at timestamp with time zone,
    CONSTRAINT event_purchase_amount_minor_check CHECK ((amount_minor >= 0)),
    CONSTRAINT event_purchase_currency_code_check CHECK ((btrim(currency_code) <> ''::text)),
    CONSTRAINT event_purchase_discount_amount_minor_check CHECK ((discount_amount_minor >= 0)),
    CONSTRAINT event_purchase_discount_code_check CHECK ((btrim(discount_code) <> ''::text)),
    CONSTRAINT event_purchase_provider_checkout_session_id_check CHECK ((btrim(provider_checkout_session_id) <> ''::text)),
    CONSTRAINT event_purchase_provider_checkout_url_check CHECK ((btrim(provider_checkout_url) <> ''::text)),
    CONSTRAINT event_purchase_provider_payment_reference_check CHECK ((btrim(provider_payment_reference) <> ''::text)),
    CONSTRAINT event_purchase_status_check CHECK ((status = ANY (ARRAY['completed'::text, 'expired'::text, 'pending'::text, 'refund-pending'::text, 'refund-requested'::text, 'refunded'::text]))),
    CONSTRAINT event_purchase_ticket_title_check CHECK ((btrim(ticket_title) <> ''::text))
);

CREATE TABLE public.event_refund_request (
    event_refund_request_id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    event_purchase_id uuid NOT NULL,
    requested_by_user_id uuid NOT NULL,
    status text NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    requested_reason text,
    review_note text,
    reviewed_at timestamp with time zone,
    reviewed_by_user_id uuid,
    CONSTRAINT event_refund_request_requested_reason_check CHECK ((btrim(requested_reason) <> ''::text)),
    CONSTRAINT event_refund_request_review_note_check CHECK ((btrim(review_note) <> ''::text)),
    CONSTRAINT event_refund_request_status_check CHECK ((status = ANY (ARRAY['approved'::text, 'approving'::text, 'pending'::text, 'rejected'::text])))
);

CREATE TABLE public.event_series (
    event_series_id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    group_id uuid NOT NULL,
    recurrence_additional_occurrences integer NOT NULL,
    recurrence_anchor_starts_at timestamp with time zone NOT NULL,
    recurrence_pattern text NOT NULL,
    timezone text NOT NULL,
    created_by uuid,
    CONSTRAINT event_series_recurrence_additional_occurrences_check CHECK (((recurrence_additional_occurrences >= 1) AND (recurrence_additional_occurrences <= 12))),
    CONSTRAINT event_series_recurrence_pattern_check CHECK ((recurrence_pattern = ANY (ARRAY['weekly'::text, 'biweekly'::text, 'monthly'::text]))),
    CONSTRAINT event_series_timezone_check CHECK ((btrim(timezone) <> ''::text))
);

CREATE TABLE public.event_speaker (
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    event_id uuid NOT NULL,
    featured boolean DEFAULT false NOT NULL,
    user_id uuid NOT NULL
);

CREATE TABLE public.event_sponsor (
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    event_id uuid NOT NULL,
    group_sponsor_id uuid NOT NULL,
    level text NOT NULL,
    CONSTRAINT event_sponsor_level_check CHECK ((btrim(level) <> ''::text))
);

CREATE TABLE public.event_ticket_price_window (
    event_ticket_price_window_id uuid NOT NULL,
    amount_minor bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    event_ticket_type_id uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ends_at timestamp with time zone,
    starts_at timestamp with time zone,
    CONSTRAINT event_ticket_price_window_amount_minor_check CHECK ((amount_minor >= 0)),
    CONSTRAINT event_ticket_price_window_window_chk CHECK (((ends_at IS NULL) OR (starts_at IS NULL) OR (ends_at >= starts_at)))
);

CREATE TABLE public.event_ticket_type (
    event_ticket_type_id uuid NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    event_id uuid NOT NULL,
    "order" integer NOT NULL,
    seats_total integer NOT NULL,
    title text NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    description text,
    CONSTRAINT event_ticket_type_description_check CHECK ((btrim(description) <> ''::text)),
    CONSTRAINT event_ticket_type_seats_total_check CHECK ((seats_total >= 0)),
    CONSTRAINT event_ticket_type_title_check CHECK ((btrim(title) <> ''::text))
);

CREATE TABLE public.event_views (
    event_id uuid,
    day date NOT NULL,
    total integer NOT NULL
);

CREATE TABLE public.event_waitlist (
    event_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE public."group" (
    group_id uuid DEFAULT gen_random_uuid() NOT NULL,
    active boolean DEFAULT true NOT NULL,
    alliance_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted boolean DEFAULT false NOT NULL,
    group_category_id uuid NOT NULL,
    group_site_layout_id text DEFAULT 'default'::text NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    tsdoc tsvector GENERATED ALWAYS AS (((((setweight(to_tsvector('simple'::regconfig, name), 'A'::"char") || setweight(to_tsvector('simple'::regconfig, public.i_array_to_string(COALESCE(tags, '{}'::text[]), ' '::text)), 'B'::"char")) || setweight(to_tsvector('simple'::regconfig, COALESCE(city, ''::text)), 'C'::"char")) || setweight(to_tsvector('simple'::regconfig, COALESCE(state, ''::text)), 'C'::"char")) || setweight(to_tsvector('simple'::regconfig, COALESCE(country_name, ''::text)), 'C'::"char"))) STORED NOT NULL,
    banner_url text,
    city text,
    country_code text,
    country_name text,
    deleted_at timestamp with time zone,
    description text,
    description_short text,
    extra_links jsonb,
    facebook_url text,
    flickr_url text,
    github_url text,
    instagram_url text,
    legacy_id integer,
    linkedin_url text,
    location public.geography(Point,4326),
    logo_url text,
    photos_urls text[],
    region_id uuid,
    slack_url text,
    state text,
    tags text[],
    twitter_url text,
    website_url text,
    wechat_url text,
    youtube_url text,
    banner_mobile_url text,
    legacy_url text,
    bluesky_url text,
    payment_recipient jsonb,
    slug_pretty text,
    og_image_url text,
    CONSTRAINT group_banner_mobile_url_check CHECK ((btrim(banner_mobile_url) <> ''::text)),
    CONSTRAINT group_banner_url_check CHECK ((btrim(banner_url) <> ''::text)),
    CONSTRAINT group_bluesky_url_check CHECK ((btrim(bluesky_url) <> ''::text)),
    CONSTRAINT group_check CHECK (((deleted = false) OR ((deleted = true) AND (active = false)))),
    CONSTRAINT group_city_check CHECK ((btrim(city) <> ''::text)),
    CONSTRAINT group_country_code_check CHECK ((btrim(country_code) <> ''::text)),
    CONSTRAINT group_country_name_check CHECK ((btrim(country_name) <> ''::text)),
    CONSTRAINT group_description_check CHECK ((btrim(description) <> ''::text)),
    CONSTRAINT group_description_short_check CHECK ((btrim(description_short) <> ''::text)),
    CONSTRAINT group_facebook_url_check CHECK ((btrim(facebook_url) <> ''::text)),
    CONSTRAINT group_flickr_url_check CHECK ((btrim(flickr_url) <> ''::text)),
    CONSTRAINT group_github_url_check CHECK ((btrim(github_url) <> ''::text)),
    CONSTRAINT group_instagram_url_check CHECK ((btrim(instagram_url) <> ''::text)),
    CONSTRAINT group_legacy_url_check CHECK ((btrim(legacy_url) <> ''::text)),
    CONSTRAINT group_linkedin_url_check CHECK ((btrim(linkedin_url) <> ''::text)),
    CONSTRAINT group_logo_url_check CHECK ((btrim(logo_url) <> ''::text)),
    CONSTRAINT group_name_check CHECK ((btrim(name) <> ''::text)),
    CONSTRAINT group_og_image_url_check CHECK ((btrim(og_image_url) <> ''::text)),
    CONSTRAINT group_slack_url_check CHECK ((btrim(slack_url) <> ''::text)),
    CONSTRAINT group_slug_check CHECK ((btrim(slug) <> ''::text)),
    CONSTRAINT group_slug_pretty_chk CHECK (((slug_pretty IS NULL) OR ((char_length(slug_pretty) <= 50) AND (slug_pretty ~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$'::text) AND (slug_pretty !~~ '%--%'::text)))),
    CONSTRAINT group_state_check CHECK ((btrim(state) <> ''::text)),
    CONSTRAINT group_twitter_url_check CHECK ((btrim(twitter_url) <> ''::text)),
    CONSTRAINT group_website_url_check CHECK ((btrim(website_url) <> ''::text)),
    CONSTRAINT group_wechat_url_check CHECK ((btrim(wechat_url) <> ''::text)),
    CONSTRAINT group_youtube_url_check CHECK ((btrim(youtube_url) <> ''::text))
);

CREATE TABLE public.group_category (
    group_category_id uuid DEFAULT gen_random_uuid() NOT NULL,
    alliance_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    name text NOT NULL,
    normalized_name text GENERATED ALWAYS AS (regexp_replace(lower(name), '[^\w]+'::text, '-'::text, 'g'::text)) STORED NOT NULL,
    "order" integer,
    CONSTRAINT group_category_name_check CHECK ((btrim(name) <> ''::text)),
    CONSTRAINT group_category_normalized_name_check CHECK ((btrim(normalized_name) <> ''::text))
);

CREATE TABLE public.group_member (
    group_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE public.group_permission (
    group_permission_id text NOT NULL,
    display_name text NOT NULL,
    CONSTRAINT group_permission_display_name_check CHECK ((btrim(display_name) <> ''::text))
);

CREATE TABLE public.group_role (
    group_role_id text NOT NULL,
    display_name text NOT NULL,
    CONSTRAINT group_role_display_name_check CHECK ((btrim(display_name) <> ''::text))
);

CREATE TABLE public.group_role_group_permission (
    group_permission_id text NOT NULL,
    group_role_id text NOT NULL
);

CREATE TABLE public.group_site_layout (
    group_site_layout_id text NOT NULL
);

CREATE TABLE public.group_sponsor (
    group_sponsor_id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    group_id uuid NOT NULL,
    logo_url text NOT NULL,
    name text NOT NULL,
    website_url text,
    featured boolean DEFAULT true NOT NULL,
    CONSTRAINT group_sponsor_logo_url_check CHECK ((btrim(logo_url) <> ''::text)),
    CONSTRAINT group_sponsor_name_check CHECK ((btrim(name) <> ''::text)),
    CONSTRAINT group_sponsor_website_url_check CHECK ((btrim(website_url) <> ''::text))
);

CREATE TABLE public.group_team (
    group_id uuid NOT NULL,
    user_id uuid NOT NULL,
    accepted boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    role text NOT NULL,
    "order" integer
);

CREATE TABLE public.group_views (
    group_id uuid,
    day date NOT NULL,
    total integer NOT NULL
);

CREATE TABLE public.images (
    file_name text NOT NULL,
    content_type text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by uuid NOT NULL,
    data bytea NOT NULL
);

CREATE TABLE public.legacy_event_host (
    legacy_event_host_id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    bio text,
    name text,
    photo_url text,
    title text,
    CONSTRAINT legacy_event_host_bio_check CHECK ((btrim(bio) <> ''::text)),
    CONSTRAINT legacy_event_host_name_check CHECK ((btrim(name) <> ''::text)),
    CONSTRAINT legacy_event_host_photo_url_check CHECK ((btrim(photo_url) <> ''::text)),
    CONSTRAINT legacy_event_host_title_check CHECK ((btrim(title) <> ''::text))
);

CREATE TABLE public.legacy_event_speaker (
    legacy_event_speaker_id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    bio text,
    name text,
    photo_url text,
    title text,
    CONSTRAINT legacy_event_speaker_bio_check CHECK ((btrim(bio) <> ''::text)),
    CONSTRAINT legacy_event_speaker_name_check CHECK ((btrim(name) <> ''::text)),
    CONSTRAINT legacy_event_speaker_photo_url_check CHECK ((btrim(photo_url) <> ''::text)),
    CONSTRAINT legacy_event_speaker_title_check CHECK ((btrim(title) <> ''::text))
);

CREATE TABLE public.meeting (
    meeting_id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    join_url text NOT NULL,
    meeting_provider_id text NOT NULL,
    provider_meeting_id text NOT NULL,
    event_id uuid,
    password text,
    session_id uuid,
    updated_at timestamp with time zone,
    provider_host_user_id text,
    auto_end_check_at timestamp with time zone,
    auto_end_check_outcome text,
    auto_end_check_claimed_at timestamp with time zone,
    sync_claimed_at timestamp with time zone,
    recording_urls text[] DEFAULT ARRAY[]::text[] NOT NULL,
    CONSTRAINT meeting_auto_end_check_pair_chk CHECK ((((auto_end_check_at IS NULL) AND (auto_end_check_outcome IS NULL)) OR ((auto_end_check_at IS NOT NULL) AND (auto_end_check_outcome IS NOT NULL)))),
    CONSTRAINT meeting_join_url_check CHECK ((btrim(join_url) <> ''::text)),
    CONSTRAINT meeting_provider_host_user_id_check CHECK ((btrim(provider_host_user_id) <> ''::text)),
    CONSTRAINT meeting_provider_meeting_id_check CHECK ((btrim(provider_meeting_id) <> ''::text)),
    CONSTRAINT meeting_recording_urls_not_empty_chk CHECK (((array_position(recording_urls, NULL::text) IS NULL) AND (array_position(recording_urls, ''::text) IS NULL)))
);

CREATE TABLE public.meeting_auto_end_check_outcome (
    meeting_auto_end_check_outcome_id text NOT NULL,
    display_name text NOT NULL,
    CONSTRAINT meeting_auto_end_check_outcome_display_name_check CHECK ((btrim(display_name) <> ''::text))
);

CREATE TABLE public.meeting_provider (
    meeting_provider_id text NOT NULL,
    display_name text NOT NULL,
    CONSTRAINT meeting_provider_display_name_check CHECK ((btrim(display_name) <> ''::text))
);

CREATE TABLE public.notification (
    notification_id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    kind text NOT NULL,
    user_id uuid NOT NULL,
    error text,
    notification_template_data_id uuid,
    processed_at timestamp with time zone,
    delivery_attempts integer DEFAULT 0 NOT NULL,
    delivery_claimed_at timestamp with time zone,
    delivery_status text DEFAULT 'pending'::text NOT NULL,
    CONSTRAINT notification_delivery_attempts_chk CHECK ((delivery_attempts >= 0)),
    CONSTRAINT notification_delivery_status_chk CHECK ((delivery_status = ANY (ARRAY['delivery-unknown'::text, 'failed'::text, 'pending'::text, 'processed'::text, 'processing'::text]))),
    CONSTRAINT notification_error_check CHECK ((btrim(error) <> ''::text))
);

CREATE TABLE public.notification_attachment (
    notification_id uuid NOT NULL,
    attachment_id uuid NOT NULL
);

CREATE TABLE public.notification_kind (
    notification_kind_id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    optional_notification boolean DEFAULT false NOT NULL,
    CONSTRAINT notification_kind_name_check CHECK ((btrim(name) <> ''::text))
);

CREATE TABLE public.notification_template_data (
    notification_template_data_id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    data jsonb NOT NULL,
    hash text NOT NULL
);

CREATE TABLE public.payment_provider (
    payment_provider_id text NOT NULL,
    display_name text NOT NULL,
    CONSTRAINT payment_provider_display_name_check CHECK ((btrim(display_name) <> ''::text))
);

CREATE TABLE public.region (
    region_id uuid DEFAULT gen_random_uuid() NOT NULL,
    alliance_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    name text NOT NULL,
    normalized_name text GENERATED ALWAYS AS (regexp_replace(lower(name), '[^\w]+'::text, '-'::text, 'g'::text)) STORED NOT NULL,
    "order" integer,
    CONSTRAINT region_name_check CHECK ((btrim(name) <> ''::text)),
    CONSTRAINT region_normalized_name_check CHECK ((btrim(normalized_name) <> ''::text))
);

CREATE TABLE public.session (
    session_id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    event_id uuid NOT NULL,
    name text NOT NULL,
    session_kind_id text NOT NULL,
    starts_at timestamp with time zone NOT NULL,
    description text,
    ends_at timestamp with time zone,
    location text,
    meeting_error text,
    meeting_hosts text[],
    meeting_in_sync boolean,
    meeting_join_url text,
    meeting_provider_id text,
    meeting_recording_url text,
    meeting_requested boolean,
    cfs_submission_id uuid,
    meeting_provider_host_user text,
    meeting_sync_claimed_at timestamp with time zone,
    meeting_join_instructions text,
    meeting_recording_published boolean DEFAULT false NOT NULL,
    CONSTRAINT session_check CHECK (((ends_at IS NULL) OR ((starts_at IS NOT NULL) AND (ends_at >= starts_at)))),
    CONSTRAINT session_description_check CHECK ((btrim(description) <> ''::text)),
    CONSTRAINT session_location_check CHECK ((btrim(location) <> ''::text)),
    CONSTRAINT session_meeting_conflict_chk CHECK ((NOT ((meeting_requested = true) AND ((meeting_join_instructions IS NOT NULL) OR (meeting_join_url IS NOT NULL))))),
    CONSTRAINT session_meeting_error_check CHECK ((btrim(meeting_error) <> ''::text)),
    CONSTRAINT session_meeting_join_instructions_check CHECK ((btrim(meeting_join_instructions) <> ''::text)),
    CONSTRAINT session_meeting_join_url_check CHECK ((btrim(meeting_join_url) <> ''::text)),
    CONSTRAINT session_meeting_provider_host_user_check CHECK ((btrim(meeting_provider_host_user) <> ''::text)),
    CONSTRAINT session_meeting_provider_required_chk CHECK ((NOT ((meeting_requested = true) AND (meeting_provider_id IS NULL)))),
    CONSTRAINT session_meeting_recording_url_check CHECK ((btrim(meeting_recording_url) <> ''::text)),
    CONSTRAINT session_meeting_requested_times_chk CHECK ((NOT ((meeting_requested = true) AND ((starts_at IS NULL) OR (ends_at IS NULL))))),
    CONSTRAINT session_name_check CHECK ((btrim(name) <> ''::text))
);

CREATE TABLE public.session_kind (
    session_kind_id text NOT NULL,
    display_name text NOT NULL
);

CREATE TABLE public.session_proposal (
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    description text NOT NULL,
    duration interval NOT NULL,
    session_proposal_id uuid DEFAULT gen_random_uuid() NOT NULL,
    session_proposal_level_id text NOT NULL,
    title text NOT NULL,
    user_id uuid NOT NULL,
    co_speaker_user_id uuid,
    updated_at timestamp with time zone,
    session_proposal_status_id text DEFAULT 'ready-for-submission'::text NOT NULL,
    CONSTRAINT session_proposal_check CHECK (((co_speaker_user_id IS NULL) OR (co_speaker_user_id <> user_id))),
    CONSTRAINT session_proposal_description_check CHECK ((btrim(description) <> ''::text)),
    CONSTRAINT session_proposal_title_check CHECK ((btrim(title) <> ''::text))
);

CREATE TABLE public.session_proposal_level (
    session_proposal_level_id text NOT NULL,
    display_name text NOT NULL,
    CONSTRAINT session_proposal_level_display_name_check CHECK ((btrim(display_name) <> ''::text))
);

CREATE TABLE public.session_proposal_status (
    session_proposal_status_id text NOT NULL,
    display_name text NOT NULL,
    CONSTRAINT session_proposal_status_display_name_check CHECK ((btrim(display_name) <> ''::text))
);

CREATE TABLE public.session_speaker (
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    featured boolean DEFAULT false NOT NULL,
    session_id uuid NOT NULL,
    user_id uuid NOT NULL
);

CREATE TABLE public.site (
    site_id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    description text NOT NULL,
    theme jsonb NOT NULL,
    title text NOT NULL,
    copyright_notice text,
    favicon_url text,
    footer_logo_url text,
    header_logo_url text,
    og_image_url text,
    CONSTRAINT site_copyright_notice_check CHECK ((btrim(copyright_notice) <> ''::text)),
    CONSTRAINT site_description_check CHECK ((btrim(description) <> ''::text)),
    CONSTRAINT site_favicon_url_check CHECK ((btrim(favicon_url) <> ''::text)),
    CONSTRAINT site_footer_logo_url_check CHECK ((btrim(footer_logo_url) <> ''::text)),
    CONSTRAINT site_header_logo_url_check CHECK ((btrim(header_logo_url) <> ''::text)),
    CONSTRAINT site_og_image_url_check CHECK ((btrim(og_image_url) <> ''::text)),
    CONSTRAINT site_title_check CHECK ((btrim(title) <> ''::text))
);

CREATE TABLE public."user" (
    user_id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    email text NOT NULL,
    email_verified boolean DEFAULT false NOT NULL,
    username text NOT NULL,
    bio text,
    city text,
    company text,
    country text,
    facebook_url text,
    interests text[],
    legacy_id integer,
    linkedin_url text,
    mentorship_businesses boolean DEFAULT false NOT NULL,
    mentorship_individuals boolean DEFAULT false NOT NULL,
    mentorship_note text,
    mentorship_price text,
    name text,
    password text,
    photo_url text,
    timezone text,
    title text,
    twitter_url text,
    website_url text,
    bluesky_url text,
    provider jsonb,
    optional_notifications_enabled boolean DEFAULT true NOT NULL,
    github_url text,
    registration_status text DEFAULT 'registered'::text NOT NULL,
    CONSTRAINT user_auth_hash_check CHECK ((btrim(auth_hash) <> ''::text)),
    CONSTRAINT user_bio_check CHECK ((btrim(bio) <> ''::text)),
    CONSTRAINT user_bluesky_url_check CHECK ((btrim(bluesky_url) <> ''::text)),
    CONSTRAINT user_city_check CHECK ((btrim(city) <> ''::text)),
    CONSTRAINT user_company_check CHECK ((btrim(company) <> ''::text)),
    CONSTRAINT user_country_check CHECK ((btrim(country) <> ''::text)),
    CONSTRAINT user_email_check CHECK ((btrim(email) <> ''::text)),
    CONSTRAINT user_facebook_url_check CHECK ((btrim(facebook_url) <> ''::text)),
    CONSTRAINT user_github_url_check CHECK ((btrim(github_url) <> ''::text)),
    CONSTRAINT user_linkedin_url_check CHECK ((btrim(linkedin_url) <> ''::text)),
    CONSTRAINT user_mentorship_note_check CHECK ((btrim(mentorship_note) <> ''::text)),
    CONSTRAINT user_mentorship_price_check CHECK ((btrim(mentorship_price) <> ''::text)),
    CONSTRAINT user_password_check CHECK ((btrim(password) <> ''::text)),
    CONSTRAINT user_photo_url_check CHECK ((btrim(photo_url) <> ''::text)),
    CONSTRAINT user_registration_status_check CHECK ((registration_status = ANY (ARRAY['pre-registered'::text, 'registered'::text]))),
    CONSTRAINT user_timezone_check CHECK ((btrim(timezone) <> ''::text)),
    CONSTRAINT user_title_check CHECK ((btrim(title) <> ''::text)),
    CONSTRAINT user_twitter_url_check CHECK ((btrim(twitter_url) <> ''::text)),
    CONSTRAINT user_username_check CHECK ((btrim(username) <> ''::text)),
    CONSTRAINT user_website_url_check CHECK ((btrim(website_url) <> ''::text))
);

CREATE TABLE public.mentorship_request (
    mentorship_request_id uuid DEFAULT gen_random_uuid() NOT NULL,
    mentor_user_id uuid NOT NULL,
    requester_user_id uuid NOT NULL,
    audience_type text NOT NULL,
    message text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT mentorship_request_audience_type_check CHECK ((audience_type = ANY (ARRAY['individual'::text, 'business'::text]))),
    CONSTRAINT mentorship_request_message_check CHECK ((btrim(message) <> ''::text))
);

INSERT INTO public.alliance_permission VALUES
	('alliance.groups.write', 'Groups Write'),
	('alliance.read', 'Read'),
	('alliance.settings.write', 'Settings Write'),
	('alliance.taxonomy.write', 'Taxonomy Write'),
	('alliance.team.write', 'Team Write');

INSERT INTO public.alliance_role VALUES
	('admin', 'Admin'),
	('groups-manager', 'Groups Manager'),
	('viewer', 'Viewer');

INSERT INTO public.alliance_role_alliance_permission VALUES
	('alliance.groups.write', 'admin'),
	('alliance.read', 'admin'),
	('alliance.settings.write', 'admin'),
	('alliance.taxonomy.write', 'admin'),
	('alliance.team.write', 'admin'),
	('alliance.groups.write', 'groups-manager'),
	('alliance.read', 'groups-manager'),
	('alliance.read', 'viewer');

INSERT INTO public.alliance_role_group_permission VALUES
	('admin', 'group.events.write'),
	('admin', 'group.members.write'),
	('admin', 'group.read'),
	('admin', 'group.settings.write'),
	('admin', 'group.sponsors.write'),
	('admin', 'group.team.write'),
	('groups-manager', 'group.events.write'),
	('groups-manager', 'group.members.write'),
	('groups-manager', 'group.read'),
	('groups-manager', 'group.settings.write'),
	('groups-manager', 'group.sponsors.write'),
	('groups-manager', 'group.team.write'),
	('viewer', 'group.read');

INSERT INTO public.alliance_site_layout VALUES
	('default');

INSERT INTO public.cfs_submission_status VALUES
	('approved', 'Approved'),
	('information-requested', 'Information requested'),
	('not-reviewed', 'Not reviewed'),
	('rejected', 'Rejected'),
	('withdrawn', 'Withdrawn');

INSERT INTO public.event_kind VALUES
	('in-person', 'In Person'),
	('virtual', 'Virtual'),
	('hybrid', 'Hybrid');

INSERT INTO public.group_permission VALUES
	('group.events.write', 'Events Write'),
	('group.members.write', 'Members Write'),
	('group.read', 'Read'),
	('group.settings.write', 'Settings Write'),
	('group.sponsors.write', 'Sponsors Write'),
	('group.team.write', 'Team Write');

INSERT INTO public.group_role VALUES
	('admin', 'Admin'),
	('events-manager', 'Events Manager'),
	('viewer', 'Viewer');

INSERT INTO public.group_role_group_permission VALUES
	('group.events.write', 'admin'),
	('group.members.write', 'admin'),
	('group.read', 'admin'),
	('group.settings.write', 'admin'),
	('group.sponsors.write', 'admin'),
	('group.team.write', 'admin'),
	('group.events.write', 'events-manager'),
	('group.read', 'events-manager'),
	('group.read', 'viewer');

INSERT INTO public.group_site_layout VALUES
	('default');

INSERT INTO public.meeting_auto_end_check_outcome VALUES
	('already_not_running', 'Already not running'),
	('auto_ended', 'Auto ended'),
	('error', 'Error'),
	('not_found', 'Not found');

INSERT INTO public.meeting_provider VALUES
	('zoom', 'Zoom');

INSERT INTO public.notification_kind VALUES
	('ea8ed9de-7770-4ecb-b2fa-4986e4af2656', 'alliance-team-invitation', false),
	('3cee28bd-d785-48f2-8ea2-ec90846b2d6a', 'email-verification', false),
	('9a77b969-4c09-450a-a0f8-7a1a53be6956', 'event-canceled', false),
	('e5ad8fe0-d86c-4c9f-a26b-3d73c07834f1', 'event-rescheduled', false),
	('b4dec9ba-386b-4127-87cd-257e65059164', 'event-welcome', false),
	('23d1f81b-b47d-4c6e-a45d-eecd016890e1', 'group-team-invitation', false),
	('badbde2f-92f1-4ebe-89b4-497e799e4f53', 'group-welcome', false),
	('2d51e540-c126-4496-b522-f69a35ef6c22', 'speaker-welcome', false),
	('523bf338-d9be-4c6d-aaf5-fd214347e2c9', 'cfs-submission-updated', false),
	('b7aacd1a-2c78-4a5b-8d24-a4c8e5033ae0', 'session-proposal-co-speaker-invitation', false),
	('3adcb81d-1465-4645-ab95-6067cecc1478', 'event-waitlist-joined', false),
	('a5c6742a-7acb-4fb9-8a78-cfb8bc6fd67f', 'event-waitlist-left', false),
	('bca68ff4-9402-45c5-9647-80ccbb974a24', 'event-waitlist-promoted', false),
	('387eac9e-a1bc-4309-bed7-5d62cff2843f', 'event-refund-approved', false),
	('eec055b7-e4d3-4f36-9105-84fbb9e27771', 'event-refund-rejected', false),
	('6369393c-7930-4fd5-b013-094c3532d6b2', 'event-refund-requested', false),
	('1043265e-afc6-48e9-b45b-091aba4e033b', 'event-series-canceled', false),
	('bc3736cd-179b-4dde-a841-981487d9f979', 'speaker-series-welcome', false),
	('1ad1a244-fda1-40a8-9f71-3fd15851b486', 'event-custom', true),
	('dea1d330-3029-4d56-aef6-8b2365d9f604', 'event-published', true),
	('79025469-e450-4f97-847c-2ebf55472c9b', 'group-custom', true),
	('a853110a-6886-4686-9904-780a0ef31117', 'event-reminder', true),
	('ca22693f-dfa9-4f0e-bb91-2807b93b829e', 'event-series-published', true),
	('65c0d38c-afbc-4379-a11d-fbc4932f2e49', 'event-invitation', false),
	('77306f02-6a1f-4a2c-bb55-59e188a29e92', 'event-attendance-canceled', false);

INSERT INTO public.payment_provider VALUES
	('stripe', 'Stripe');

INSERT INTO public.session_kind VALUES
	('hybrid', 'Hybrid'),
	('in-person', 'In-Person'),
	('virtual', 'Virtual');

INSERT INTO public.session_proposal_level VALUES
	('advanced', 'Advanced'),
	('beginner', 'Beginner'),
	('intermediate', 'Intermediate');

INSERT INTO public.session_proposal_status VALUES
	('declined-by-co-speaker', 'Declined by co-speaker'),
	('pending-co-speaker-response', 'Awaiting co-speaker response'),
	('ready-for-submission', 'Ready for submission');

ALTER TABLE ONLY public.alliance
    ADD CONSTRAINT alliance_display_name_key UNIQUE (display_name);

ALTER TABLE ONLY public.alliance
    ADD CONSTRAINT alliance_name_key UNIQUE (name);

ALTER TABLE ONLY public.alliance_permission
    ADD CONSTRAINT alliance_permission_display_name_key UNIQUE (display_name);

ALTER TABLE ONLY public.alliance_permission
    ADD CONSTRAINT alliance_permission_pkey PRIMARY KEY (alliance_permission_id);

ALTER TABLE ONLY public.alliance
    ADD CONSTRAINT alliance_pkey PRIMARY KEY (alliance_id);

ALTER TABLE ONLY public.alliance_redirect_settings
    ADD CONSTRAINT alliance_redirect_settings_pkey PRIMARY KEY (alliance_id);

ALTER TABLE ONLY public.alliance_role_alliance_permission
    ADD CONSTRAINT alliance_role_alliance_permission_pkey PRIMARY KEY (alliance_permission_id, alliance_role_id);

ALTER TABLE ONLY public.alliance_role
    ADD CONSTRAINT alliance_role_display_name_key UNIQUE (display_name);

ALTER TABLE ONLY public.alliance_role_group_permission
    ADD CONSTRAINT alliance_role_group_permission_pkey PRIMARY KEY (alliance_role_id, group_permission_id);

ALTER TABLE ONLY public.alliance_role
    ADD CONSTRAINT alliance_role_pkey PRIMARY KEY (alliance_role_id);

ALTER TABLE ONLY public.alliance_site_layout
    ADD CONSTRAINT alliance_site_layout_pkey PRIMARY KEY (alliance_site_layout_id);

ALTER TABLE ONLY public.alliance_team
    ADD CONSTRAINT alliance_team_pkey PRIMARY KEY (alliance_id, user_id);

ALTER TABLE ONLY public.alliance_views
    ADD CONSTRAINT alliance_views_alliance_id_day_key UNIQUE (alliance_id, day);

ALTER TABLE ONLY public.attachment
    ADD CONSTRAINT attachment_hash_idx UNIQUE (hash);

ALTER TABLE ONLY public.attachment
    ADD CONSTRAINT attachment_pkey PRIMARY KEY (attachment_id);

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (audit_log_id);

ALTER TABLE ONLY public.auth_session
    ADD CONSTRAINT auth_session_pkey PRIMARY KEY (auth_session_id);

ALTER TABLE ONLY public.cfs_submission
    ADD CONSTRAINT cfs_submission_event_id_session_proposal_id_key UNIQUE (event_id, session_proposal_id);

ALTER TABLE ONLY public.cfs_submission_label
    ADD CONSTRAINT cfs_submission_label_pkey PRIMARY KEY (cfs_submission_id, event_cfs_label_id);

ALTER TABLE ONLY public.cfs_submission
    ADD CONSTRAINT cfs_submission_pkey PRIMARY KEY (cfs_submission_id);

ALTER TABLE ONLY public.cfs_submission_rating
    ADD CONSTRAINT cfs_submission_rating_pkey PRIMARY KEY (cfs_submission_id, reviewer_id);

ALTER TABLE ONLY public.cfs_submission_status
    ADD CONSTRAINT cfs_submission_status_display_name_key UNIQUE (display_name);

ALTER TABLE ONLY public.cfs_submission_status
    ADD CONSTRAINT cfs_submission_status_pkey PRIMARY KEY (cfs_submission_status_id);

ALTER TABLE ONLY public.custom_notification
    ADD CONSTRAINT custom_notification_pkey PRIMARY KEY (custom_notification_id);

ALTER TABLE ONLY public.email_verification_code
    ADD CONSTRAINT email_verification_code_pkey PRIMARY KEY (email_verification_code_id);

ALTER TABLE ONLY public.email_verification_code
    ADD CONSTRAINT email_verification_code_user_id_key UNIQUE (user_id);

ALTER TABLE ONLY public.event_attendee
    ADD CONSTRAINT event_attendee_pkey PRIMARY KEY (event_id, user_id);

ALTER TABLE ONLY public.event_category
    ADD CONSTRAINT event_category_name_alliance_id_key UNIQUE (name, alliance_id);

ALTER TABLE ONLY public.event_category
    ADD CONSTRAINT event_category_pkey PRIMARY KEY (event_category_id);

ALTER TABLE ONLY public.event_category
    ADD CONSTRAINT event_category_slug_alliance_id_key UNIQUE (slug, alliance_id);

ALTER TABLE ONLY public.event_cfs_label
    ADD CONSTRAINT event_cfs_label_event_id_name_key UNIQUE (event_id, name);

ALTER TABLE ONLY public.event_cfs_label
    ADD CONSTRAINT event_cfs_label_pkey PRIMARY KEY (event_cfs_label_id);

ALTER TABLE ONLY public.event_discount_code
    ADD CONSTRAINT event_discount_code_event_id_event_discount_code_id_key UNIQUE (event_id, event_discount_code_id);

ALTER TABLE ONLY public.event_discount_code
    ADD CONSTRAINT event_discount_code_pkey PRIMARY KEY (event_discount_code_id);

ALTER TABLE ONLY public.event_host
    ADD CONSTRAINT event_host_pkey PRIMARY KEY (event_id, user_id);

ALTER TABLE ONLY public.event_invitation_request
    ADD CONSTRAINT event_invitation_request_pkey PRIMARY KEY (event_id, user_id);

ALTER TABLE ONLY public.event_kind
    ADD CONSTRAINT event_kind_display_name_key UNIQUE (display_name);

ALTER TABLE ONLY public.event_kind
    ADD CONSTRAINT event_kind_pkey PRIMARY KEY (event_kind_id);

ALTER TABLE ONLY public.event_organizer
    ADD CONSTRAINT event_organizer_pkey PRIMARY KEY (event_id, user_id);

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_pkey PRIMARY KEY (event_id);

ALTER TABLE ONLY public.event_purchase
    ADD CONSTRAINT event_purchase_pkey PRIMARY KEY (event_purchase_id);

ALTER TABLE ONLY public.event_refund_request
    ADD CONSTRAINT event_refund_request_event_purchase_id_key UNIQUE (event_purchase_id);

ALTER TABLE ONLY public.event_refund_request
    ADD CONSTRAINT event_refund_request_pkey PRIMARY KEY (event_refund_request_id);

ALTER TABLE ONLY public.event_series
    ADD CONSTRAINT event_series_pkey PRIMARY KEY (event_series_id);

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_slug_group_id_key UNIQUE (slug, group_id);

ALTER TABLE ONLY public.event_speaker
    ADD CONSTRAINT event_speaker_pkey PRIMARY KEY (event_id, user_id);

ALTER TABLE ONLY public.event_sponsor
    ADD CONSTRAINT event_sponsor_pkey PRIMARY KEY (group_sponsor_id, event_id);

ALTER TABLE ONLY public.event_ticket_price_window
    ADD CONSTRAINT event_ticket_price_window_pkey PRIMARY KEY (event_ticket_price_window_id);

ALTER TABLE ONLY public.event_ticket_type
    ADD CONSTRAINT event_ticket_type_event_id_event_ticket_type_id_key UNIQUE (event_id, event_ticket_type_id);

ALTER TABLE ONLY public.event_ticket_type
    ADD CONSTRAINT event_ticket_type_pkey PRIMARY KEY (event_ticket_type_id);

ALTER TABLE ONLY public.event_views
    ADD CONSTRAINT event_views_event_id_day_key UNIQUE (event_id, day);

ALTER TABLE ONLY public.event_waitlist
    ADD CONSTRAINT event_waitlist_pkey PRIMARY KEY (event_id, user_id);

ALTER TABLE ONLY public.group_category
    ADD CONSTRAINT group_category_name_alliance_id_key UNIQUE (name, alliance_id);

ALTER TABLE ONLY public.group_category
    ADD CONSTRAINT group_category_normalized_name_alliance_id_key UNIQUE (normalized_name, alliance_id);

ALTER TABLE ONLY public.group_category
    ADD CONSTRAINT group_category_pkey PRIMARY KEY (group_category_id);

ALTER TABLE ONLY public.group_member
    ADD CONSTRAINT group_member_pkey PRIMARY KEY (group_id, user_id);

ALTER TABLE ONLY public.group_permission
    ADD CONSTRAINT group_permission_display_name_key UNIQUE (display_name);

ALTER TABLE ONLY public.group_permission
    ADD CONSTRAINT group_permission_pkey PRIMARY KEY (group_permission_id);

ALTER TABLE ONLY public."group"
    ADD CONSTRAINT group_pkey PRIMARY KEY (group_id);

ALTER TABLE ONLY public.group_role
    ADD CONSTRAINT group_role_display_name_key UNIQUE (display_name);

ALTER TABLE ONLY public.group_role_group_permission
    ADD CONSTRAINT group_role_group_permission_pkey PRIMARY KEY (group_permission_id, group_role_id);

ALTER TABLE ONLY public.group_role
    ADD CONSTRAINT group_role_pkey PRIMARY KEY (group_role_id);

ALTER TABLE ONLY public.group_site_layout
    ADD CONSTRAINT group_site_layout_pkey PRIMARY KEY (group_site_layout_id);

ALTER TABLE ONLY public."group"
    ADD CONSTRAINT group_slug_alliance_id_key UNIQUE (slug, alliance_id);

ALTER TABLE ONLY public.group_sponsor
    ADD CONSTRAINT group_sponsor_pkey PRIMARY KEY (group_sponsor_id);

ALTER TABLE ONLY public.group_team
    ADD CONSTRAINT group_team_pkey PRIMARY KEY (group_id, user_id);

ALTER TABLE ONLY public.group_views
    ADD CONSTRAINT group_views_group_id_day_key UNIQUE (group_id, day);

ALTER TABLE ONLY public.images
    ADD CONSTRAINT images_pkey PRIMARY KEY (file_name);

ALTER TABLE ONLY public.legacy_event_host
    ADD CONSTRAINT legacy_event_host_pkey PRIMARY KEY (legacy_event_host_id);

ALTER TABLE ONLY public.legacy_event_speaker
    ADD CONSTRAINT legacy_event_speaker_pkey PRIMARY KEY (legacy_event_speaker_id);

ALTER TABLE ONLY public.meeting_auto_end_check_outcome
    ADD CONSTRAINT meeting_auto_end_check_outcome_display_name_key UNIQUE (display_name);

ALTER TABLE ONLY public.meeting_auto_end_check_outcome
    ADD CONSTRAINT meeting_auto_end_check_outcome_pkey PRIMARY KEY (meeting_auto_end_check_outcome_id);

ALTER TABLE ONLY public.meeting
    ADD CONSTRAINT meeting_pkey PRIMARY KEY (meeting_id);

ALTER TABLE ONLY public.meeting_provider
    ADD CONSTRAINT meeting_provider_display_name_key UNIQUE (display_name);

ALTER TABLE ONLY public.meeting_provider
    ADD CONSTRAINT meeting_provider_pkey PRIMARY KEY (meeting_provider_id);

ALTER TABLE ONLY public.notification_attachment
    ADD CONSTRAINT notification_attachment_pkey PRIMARY KEY (notification_id, attachment_id);

ALTER TABLE ONLY public.notification_kind
    ADD CONSTRAINT notification_kind_name_key UNIQUE (name);

ALTER TABLE ONLY public.notification_kind
    ADD CONSTRAINT notification_kind_pkey PRIMARY KEY (notification_kind_id);

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_pkey PRIMARY KEY (notification_id);

ALTER TABLE ONLY public.notification_template_data
    ADD CONSTRAINT notification_template_data_hash_idx UNIQUE (hash);

ALTER TABLE ONLY public.notification_template_data
    ADD CONSTRAINT notification_template_data_pkey PRIMARY KEY (notification_template_data_id);

ALTER TABLE ONLY public.payment_provider
    ADD CONSTRAINT payment_provider_display_name_key UNIQUE (display_name);

ALTER TABLE ONLY public.payment_provider
    ADD CONSTRAINT payment_provider_pkey PRIMARY KEY (payment_provider_id);

ALTER TABLE ONLY public.region
    ADD CONSTRAINT region_name_alliance_id_key UNIQUE (name, alliance_id);

ALTER TABLE ONLY public.region
    ADD CONSTRAINT region_normalized_name_alliance_id_key UNIQUE (normalized_name, alliance_id);

ALTER TABLE ONLY public.region
    ADD CONSTRAINT region_pkey PRIMARY KEY (region_id);

ALTER TABLE ONLY public.session_kind
    ADD CONSTRAINT session_kind_display_name_key UNIQUE (display_name);

ALTER TABLE ONLY public.session_kind
    ADD CONSTRAINT session_kind_pkey PRIMARY KEY (session_kind_id);

ALTER TABLE ONLY public.session
    ADD CONSTRAINT session_pkey PRIMARY KEY (session_id);

ALTER TABLE ONLY public.session_proposal_level
    ADD CONSTRAINT session_proposal_level_display_name_key UNIQUE (display_name);

ALTER TABLE ONLY public.session_proposal_level
    ADD CONSTRAINT session_proposal_level_pkey PRIMARY KEY (session_proposal_level_id);

ALTER TABLE ONLY public.session_proposal
    ADD CONSTRAINT session_proposal_pkey PRIMARY KEY (session_proposal_id);

ALTER TABLE ONLY public.session_proposal_status
    ADD CONSTRAINT session_proposal_status_display_name_key UNIQUE (display_name);

ALTER TABLE ONLY public.session_proposal_status
    ADD CONSTRAINT session_proposal_status_pkey PRIMARY KEY (session_proposal_status_id);

ALTER TABLE ONLY public.session_speaker
    ADD CONSTRAINT session_speaker_pkey PRIMARY KEY (session_id, user_id);

ALTER TABLE ONLY public.site
    ADD CONSTRAINT site_pkey PRIMARY KEY (site_id);

ALTER TABLE ONLY public.mentorship_request
    ADD CONSTRAINT mentorship_request_pkey PRIMARY KEY (mentorship_request_id);

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (user_id);

CREATE INDEX alliance_alliance_site_layout_id_idx ON public.alliance USING btree (alliance_site_layout_id);

CREATE INDEX alliance_og_image_url_idx ON public.alliance USING btree (og_image_url) WHERE (og_image_url IS NOT NULL);

CREATE INDEX alliance_team_alliance_id_idx ON public.alliance_team USING btree (alliance_id);

CREATE INDEX alliance_team_pending_user_created_at_idx ON public.alliance_team USING btree (user_id, created_at DESC) WHERE (accepted = false);

CREATE INDEX alliance_team_role_idx ON public.alliance_team USING btree (role);

CREATE INDEX alliance_team_user_id_idx ON public.alliance_team USING btree (user_id);

CREATE INDEX audit_log_actor_user_id_created_at_idx ON public.audit_log USING btree (actor_user_id, created_at DESC);

CREATE INDEX audit_log_alliance_id_created_at_idx ON public.audit_log USING btree (alliance_id, created_at DESC);

CREATE INDEX audit_log_created_at_idx ON public.audit_log USING btree (created_at DESC);

CREATE INDEX audit_log_group_id_created_at_idx ON public.audit_log USING btree (group_id, created_at DESC);

CREATE INDEX audit_log_resource_type_resource_id_created_at_idx ON public.audit_log USING btree (resource_type, resource_id, created_at DESC);

CREATE INDEX cfs_submission_event_id_idx ON public.cfs_submission USING btree (event_id);

CREATE INDEX cfs_submission_label_event_cfs_label_id_idx ON public.cfs_submission_label USING btree (event_cfs_label_id);

CREATE INDEX cfs_submission_rating_reviewer_id_idx ON public.cfs_submission_rating USING btree (reviewer_id);

CREATE INDEX cfs_submission_reviewed_by_idx ON public.cfs_submission USING btree (reviewed_by);

CREATE INDEX cfs_submission_session_proposal_id_idx ON public.cfs_submission USING btree (session_proposal_id);

CREATE INDEX cfs_submission_status_id_idx ON public.cfs_submission USING btree (status_id);

CREATE INDEX custom_notification_created_by_idx ON public.custom_notification USING btree (created_by);

CREATE INDEX custom_notification_event_id_idx ON public.custom_notification USING btree (event_id);

CREATE INDEX custom_notification_group_id_idx ON public.custom_notification USING btree (group_id);

CREATE INDEX email_verification_code_user_id_idx ON public.email_verification_code USING btree (user_id);

CREATE INDEX event_attendee_event_id_created_at_idx ON public.event_attendee USING btree (event_id, created_at);

CREATE INDEX event_attendee_event_id_idx ON public.event_attendee USING btree (event_id);

CREATE INDEX event_attendee_event_id_registration_answers_idx ON public.event_attendee USING btree (event_id) WHERE (registration_answers IS NOT NULL);

CREATE INDEX event_attendee_event_id_status_created_at_idx ON public.event_attendee USING btree (event_id, status, created_at);

CREATE INDEX event_attendee_user_id_idx ON public.event_attendee USING btree (user_id);

CREATE INDEX event_category_alliance_id_idx ON public.event_category USING btree (alliance_id);

CREATE INDEX event_cfs_label_event_id_idx ON public.event_cfs_label USING btree (event_id);

CREATE INDEX event_discount_code_event_id_idx ON public.event_discount_code USING btree (event_id);

CREATE UNIQUE INDEX event_discount_code_event_id_upper_code_idx ON public.event_discount_code USING btree (event_id, upper(code));

CREATE INDEX event_event_category_id_idx ON public.event USING btree (event_category_id);

CREATE INDEX event_event_kind_id_idx ON public.event USING btree (event_kind_id);

CREATE INDEX event_event_series_id_idx ON public.event USING btree (event_series_id) WHERE (event_series_id IS NOT NULL);

CREATE INDEX event_group_id_idx ON public.event USING btree (group_id);

CREATE INDEX event_group_not_deleted_starts_at_idx ON public.event USING btree (group_id, starts_at, event_id) WHERE (deleted = false);

CREATE INDEX event_host_event_id_idx ON public.event_host USING btree (event_id);

CREATE INDEX event_host_user_id_idx ON public.event_host USING btree (user_id);

CREATE INDEX event_invitation_request_event_id_registration_answers_idx ON public.event_invitation_request USING btree (event_id) WHERE (registration_answers IS NOT NULL);

CREATE INDEX event_invitation_request_event_id_status_created_at_idx ON public.event_invitation_request USING btree (event_id, status, created_at);

CREATE INDEX event_invitation_request_user_id_idx ON public.event_invitation_request USING btree (user_id);

CREATE INDEX event_location_idx ON public.event USING gist (location);

CREATE INDEX event_meeting_sync_claim_idx ON public.event USING btree (meeting_sync_claimed_at) WHERE (meeting_in_sync = false);

CREATE INDEX event_meeting_sync_idx ON public.event USING btree (meeting_requested, meeting_in_sync) WHERE ((meeting_requested = true) AND (meeting_in_sync = false));

CREATE INDEX event_organizer_event_id_idx ON public.event_organizer USING btree (event_id);

CREATE INDEX event_organizer_user_id_idx ON public.event_organizer USING btree (user_id);

CREATE INDEX event_published_by_idx ON public.event USING btree (published_by);

CREATE INDEX event_purchase_event_id_idx ON public.event_purchase USING btree (event_id);

CREATE INDEX event_purchase_event_id_status_idx ON public.event_purchase USING btree (event_id, status);

CREATE UNIQUE INDEX event_purchase_event_id_user_id_active_idx ON public.event_purchase USING btree (event_id, user_id) WHERE (status = ANY (ARRAY['completed'::text, 'pending'::text, 'refund-requested'::text]));

CREATE UNIQUE INDEX event_purchase_provider_checkout_session_idx ON public.event_purchase USING btree (payment_provider_id, provider_checkout_session_id) WHERE (provider_checkout_session_id IS NOT NULL);

CREATE INDEX event_purchase_user_id_idx ON public.event_purchase USING btree (user_id);

CREATE INDEX event_refund_request_status_idx ON public.event_refund_request USING btree (status);

CREATE INDEX event_search_idx ON public.event USING btree (group_id, published, canceled, starts_at) WHERE ((published = true) AND (canceled = false));

CREATE INDEX event_series_group_id_idx ON public.event_series USING btree (group_id);

CREATE INDEX event_speaker_event_id_idx ON public.event_speaker USING btree (event_id);

CREATE INDEX event_speaker_user_id_idx ON public.event_speaker USING btree (user_id);

CREATE INDEX event_sponsor_event_id_idx ON public.event_sponsor USING btree (event_id);

CREATE INDEX event_sponsor_group_sponsor_id_idx ON public.event_sponsor USING btree (group_sponsor_id);

CREATE INDEX event_starts_at_idx ON public.event USING btree (starts_at) WHERE ((published = true) AND (canceled = false) AND (deleted = false));

CREATE INDEX event_ticket_price_window_event_ticket_type_id_idx ON public.event_ticket_price_window USING btree (event_ticket_type_id);

CREATE INDEX event_ticket_type_event_id_idx ON public.event_ticket_type USING btree (event_id);

CREATE INDEX event_tsdoc_idx ON public.event USING gin (tsdoc);

CREATE INDEX event_waitlist_event_id_created_at_idx ON public.event_waitlist USING btree (event_id, created_at);

CREATE INDEX event_waitlist_user_id_idx ON public.event_waitlist USING btree (user_id);

CREATE INDEX group_active_created_at_idx ON public."group" USING btree (created_at DESC) WHERE (active = true);

CREATE INDEX group_alliance_active_created_at_idx ON public."group" USING btree (alliance_id, created_at DESC) WHERE (active = true);

CREATE INDEX group_alliance_id_idx ON public."group" USING btree (alliance_id);

CREATE INDEX group_category_alliance_id_idx ON public.group_category USING btree (alliance_id);

CREATE INDEX group_group_category_id_idx ON public."group" USING btree (group_category_id);

CREATE INDEX group_group_site_layout_id_idx ON public."group" USING btree (group_site_layout_id);

CREATE INDEX group_location_idx ON public."group" USING gist (location);

CREATE INDEX group_member_group_id_created_at_idx ON public.group_member USING btree (group_id, created_at);

CREATE INDEX group_member_group_id_idx ON public.group_member USING btree (group_id);

CREATE INDEX group_member_user_id_idx ON public.group_member USING btree (user_id);

CREATE INDEX group_og_image_url_idx ON public."group" USING btree (og_image_url) WHERE (og_image_url IS NOT NULL);

CREATE INDEX group_region_id_idx ON public."group" USING btree (region_id);

CREATE INDEX group_search_idx ON public."group" USING btree (alliance_id, active) WHERE (active = true);

CREATE UNIQUE INDEX group_slug_pretty_alliance_id_key ON public."group" USING btree (slug_pretty, alliance_id) WHERE (slug_pretty IS NOT NULL);

CREATE INDEX group_sponsor_group_id_idx ON public.group_sponsor USING btree (group_id);

CREATE INDEX group_team_group_id_idx ON public.group_team USING btree (group_id);

CREATE INDEX group_team_pending_user_created_at_idx ON public.group_team USING btree (user_id, created_at DESC) WHERE (accepted = false);

CREATE INDEX group_team_role_idx ON public.group_team USING btree (role);

CREATE INDEX group_team_user_id_idx ON public.group_team USING btree (user_id);

CREATE INDEX group_tsdoc_idx ON public."group" USING gin (tsdoc);

CREATE INDEX legacy_event_host_event_id_idx ON public.legacy_event_host USING btree (event_id);

CREATE INDEX legacy_event_speaker_event_id_idx ON public.legacy_event_speaker USING btree (event_id);

CREATE INDEX meeting_auto_end_check_claim_idx ON public.meeting USING btree (auto_end_check_claimed_at) WHERE (auto_end_check_at IS NULL);

CREATE UNIQUE INDEX meeting_event_id_idx ON public.meeting USING btree (event_id);

CREATE INDEX meeting_meeting_provider_id_idx ON public.meeting USING btree (meeting_provider_id);

CREATE INDEX meeting_meeting_provider_id_provider_host_user_id_idx ON public.meeting USING btree (meeting_provider_id, provider_host_user_id);

CREATE INDEX mentorship_request_mentor_user_id_created_at_idx ON public.mentorship_request USING btree (mentor_user_id, created_at DESC);

CREATE INDEX mentorship_request_requester_user_id_created_at_idx ON public.mentorship_request USING btree (requester_user_id, created_at DESC);

CREATE UNIQUE INDEX meeting_meeting_provider_id_provider_meeting_id_idx ON public.meeting USING btree (meeting_provider_id, provider_meeting_id);

CREATE UNIQUE INDEX meeting_session_id_idx ON public.meeting USING btree (session_id);

CREATE INDEX meeting_sync_claim_idx ON public.meeting USING btree (sync_claimed_at) WHERE ((event_id IS NULL) AND (session_id IS NULL));

CREATE INDEX meeting_zoom_auto_end_pending_idx ON public.meeting USING btree (meeting_provider_id, auto_end_check_at) WHERE ((meeting_provider_id = 'zoom'::text) AND (auto_end_check_at IS NULL));

CREATE INDEX notification_attachment_attachment_id_idx ON public.notification_attachment USING btree (attachment_id);

CREATE INDEX notification_delivery_claimed_at_idx ON public.notification USING btree (delivery_claimed_at) WHERE (delivery_claimed_at IS NOT NULL);

CREATE INDEX notification_kind_idx ON public.notification USING btree (kind);

CREATE INDEX notification_not_processed_idx ON public.notification USING btree (created_at, notification_id) WHERE (delivery_status = 'pending'::text);

CREATE INDEX notification_user_id_idx ON public.notification USING btree (user_id);

CREATE INDEX region_alliance_id_idx ON public.region USING btree (alliance_id);

CREATE UNIQUE INDEX session_cfs_submission_id_unique_idx ON public.session USING btree (cfs_submission_id) WHERE (cfs_submission_id IS NOT NULL);

CREATE INDEX session_event_id_idx ON public.session USING btree (event_id);

CREATE INDEX session_meeting_sync_claim_idx ON public.session USING btree (meeting_sync_claimed_at) WHERE (meeting_in_sync = false);

CREATE INDEX session_meeting_sync_idx ON public.session USING btree (meeting_requested, meeting_in_sync) WHERE ((meeting_requested = true) AND (meeting_in_sync = false));

CREATE INDEX session_proposal_co_speaker_user_id_idx ON public.session_proposal USING btree (co_speaker_user_id);

CREATE INDEX session_proposal_session_proposal_level_id_idx ON public.session_proposal USING btree (session_proposal_level_id);

CREATE INDEX session_proposal_status_id_idx ON public.session_proposal USING btree (session_proposal_status_id);

CREATE INDEX session_proposal_user_id_idx ON public.session_proposal USING btree (user_id);

CREATE INDEX session_session_kind_id_idx ON public.session USING btree (session_kind_id);

CREATE INDEX session_speaker_session_id_idx ON public.session_speaker USING btree (session_id);

CREATE INDEX session_speaker_user_id_idx ON public.session_speaker USING btree (user_id);

CREATE UNIQUE INDEX user_email_lower_idx ON public."user" USING btree (lower(email));

CREATE INDEX user_name_lower_idx ON public."user" USING btree (lower(name));

CREATE UNIQUE INDEX user_username_lower_idx ON public."user" USING btree (lower(username));

CREATE TRIGGER event_attendee_waitlist_check BEFORE INSERT OR UPDATE OF event_id, user_id ON public.event_attendee FOR EACH ROW EXECUTE FUNCTION public.check_event_attendee_waitlist();

CREATE TRIGGER event_category_alliance_check BEFORE INSERT OR UPDATE ON public.event FOR EACH ROW EXECUTE FUNCTION public.check_event_category_alliance();

CREATE TRIGGER event_sponsor_group_check BEFORE INSERT OR UPDATE ON public.event_sponsor FOR EACH ROW EXECUTE FUNCTION public.check_event_sponsor_group();

CREATE CONSTRAINT TRIGGER event_ticketing_consistency_on_event AFTER INSERT OR UPDATE OF payment_currency_code ON public.event DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.check_event_ticketing_consistency();

CREATE CONSTRAINT TRIGGER event_ticketing_consistency_on_event_discount_code AFTER INSERT OR DELETE OR UPDATE ON public.event_discount_code DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.check_event_ticketing_consistency();

CREATE CONSTRAINT TRIGGER event_ticketing_consistency_on_event_ticket_type AFTER INSERT OR DELETE OR UPDATE ON public.event_ticket_type DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.check_event_ticketing_consistency();

CREATE TRIGGER event_waitlist_attendee_check BEFORE INSERT OR UPDATE OF event_id, user_id ON public.event_waitlist FOR EACH ROW EXECUTE FUNCTION public.check_event_waitlist_attendee();

CREATE TRIGGER group_category_alliance_check BEFORE INSERT OR UPDATE ON public."group" FOR EACH ROW EXECUTE FUNCTION public.check_group_category_alliance();

CREATE TRIGGER group_region_alliance_check BEFORE INSERT OR UPDATE ON public."group" FOR EACH ROW EXECUTE FUNCTION public.check_group_region_alliance();

CREATE TRIGGER group_slug_pretty_validate BEFORE INSERT OR UPDATE OF slug, slug_pretty, alliance_id ON public."group" FOR EACH ROW EXECUTE FUNCTION public.validate_group_slug_pretty();

CREATE TRIGGER session_cfs_submission_approved_check BEFORE INSERT OR UPDATE ON public.session FOR EACH ROW EXECUTE FUNCTION public.check_session_cfs_submission_approved();

CREATE TRIGGER session_within_event_bounds_check BEFORE INSERT OR UPDATE ON public.session FOR EACH ROW EXECUTE FUNCTION public.check_session_within_event_bounds();

ALTER TABLE ONLY public.alliance
    ADD CONSTRAINT alliance_alliance_site_layout_id_fkey FOREIGN KEY (alliance_site_layout_id) REFERENCES public.alliance_site_layout(alliance_site_layout_id);

ALTER TABLE ONLY public.alliance_redirect_settings
    ADD CONSTRAINT alliance_redirect_settings_alliance_id_fkey FOREIGN KEY (alliance_id) REFERENCES public.alliance(alliance_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.alliance_role_alliance_permission
    ADD CONSTRAINT alliance_role_alliance_permission_alliance_permission_id_fkey FOREIGN KEY (alliance_permission_id) REFERENCES public.alliance_permission(alliance_permission_id);

ALTER TABLE ONLY public.alliance_role_alliance_permission
    ADD CONSTRAINT alliance_role_alliance_permission_alliance_role_id_fkey FOREIGN KEY (alliance_role_id) REFERENCES public.alliance_role(alliance_role_id);

ALTER TABLE ONLY public.alliance_role_group_permission
    ADD CONSTRAINT alliance_role_group_permission_alliance_role_id_fkey FOREIGN KEY (alliance_role_id) REFERENCES public.alliance_role(alliance_role_id);

ALTER TABLE ONLY public.alliance_role_group_permission
    ADD CONSTRAINT alliance_role_group_permission_group_permission_id_fkey FOREIGN KEY (group_permission_id) REFERENCES public.group_permission(group_permission_id);

ALTER TABLE ONLY public.alliance_team
    ADD CONSTRAINT alliance_team_alliance_id_fkey FOREIGN KEY (alliance_id) REFERENCES public.alliance(alliance_id);

ALTER TABLE ONLY public.alliance_team
    ADD CONSTRAINT alliance_team_role_fkey FOREIGN KEY (role) REFERENCES public.alliance_role(alliance_role_id);

ALTER TABLE ONLY public.alliance_team
    ADD CONSTRAINT alliance_team_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.alliance_views
    ADD CONSTRAINT alliance_views_alliance_id_fkey FOREIGN KEY (alliance_id) REFERENCES public.alliance(alliance_id) ON DELETE SET NULL;

ALTER TABLE ONLY public.cfs_submission
    ADD CONSTRAINT cfs_submission_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id);

ALTER TABLE ONLY public.cfs_submission_label
    ADD CONSTRAINT cfs_submission_label_cfs_submission_id_fkey FOREIGN KEY (cfs_submission_id) REFERENCES public.cfs_submission(cfs_submission_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.cfs_submission_label
    ADD CONSTRAINT cfs_submission_label_event_cfs_label_id_fkey FOREIGN KEY (event_cfs_label_id) REFERENCES public.event_cfs_label(event_cfs_label_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.cfs_submission_rating
    ADD CONSTRAINT cfs_submission_rating_cfs_submission_id_fkey FOREIGN KEY (cfs_submission_id) REFERENCES public.cfs_submission(cfs_submission_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.cfs_submission_rating
    ADD CONSTRAINT cfs_submission_rating_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.cfs_submission
    ADD CONSTRAINT cfs_submission_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.cfs_submission
    ADD CONSTRAINT cfs_submission_session_proposal_id_fkey FOREIGN KEY (session_proposal_id) REFERENCES public.session_proposal(session_proposal_id);

ALTER TABLE ONLY public.cfs_submission
    ADD CONSTRAINT cfs_submission_status_id_fkey FOREIGN KEY (status_id) REFERENCES public.cfs_submission_status(cfs_submission_status_id);

ALTER TABLE ONLY public.custom_notification
    ADD CONSTRAINT custom_notification_created_by_fkey FOREIGN KEY (created_by) REFERENCES public."user"(user_id) ON DELETE SET NULL;

ALTER TABLE ONLY public.custom_notification
    ADD CONSTRAINT custom_notification_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.custom_notification
    ADD CONSTRAINT custom_notification_group_id_fkey FOREIGN KEY (group_id) REFERENCES public."group"(group_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.email_verification_code
    ADD CONSTRAINT email_verification_code_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(user_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.event_attendee
    ADD CONSTRAINT event_attendee_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id);

ALTER TABLE ONLY public.event_attendee
    ADD CONSTRAINT event_attendee_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.event_category
    ADD CONSTRAINT event_category_alliance_id_fkey FOREIGN KEY (alliance_id) REFERENCES public.alliance(alliance_id);

ALTER TABLE ONLY public.event_cfs_label
    ADD CONSTRAINT event_cfs_label_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_created_by_fkey FOREIGN KEY (created_by) REFERENCES public."user"(user_id) ON DELETE SET NULL;

ALTER TABLE ONLY public.event_discount_code
    ADD CONSTRAINT event_discount_code_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_event_category_id_fkey FOREIGN KEY (event_category_id) REFERENCES public.event_category(event_category_id);

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_event_kind_id_fkey FOREIGN KEY (event_kind_id) REFERENCES public.event_kind(event_kind_id);

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_event_series_id_fkey FOREIGN KEY (event_series_id) REFERENCES public.event_series(event_series_id);

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_group_id_fkey FOREIGN KEY (group_id) REFERENCES public."group"(group_id);

ALTER TABLE ONLY public.event_host
    ADD CONSTRAINT event_host_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id);

ALTER TABLE ONLY public.event_host
    ADD CONSTRAINT event_host_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.event_invitation_request
    ADD CONSTRAINT event_invitation_request_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id);

ALTER TABLE ONLY public.event_invitation_request
    ADD CONSTRAINT event_invitation_request_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.event_invitation_request
    ADD CONSTRAINT event_invitation_request_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_meeting_provider_id_fkey FOREIGN KEY (meeting_provider_id) REFERENCES public.meeting_provider(meeting_provider_id);

ALTER TABLE ONLY public.event_organizer
    ADD CONSTRAINT event_organizer_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id);

ALTER TABLE ONLY public.event_organizer
    ADD CONSTRAINT event_organizer_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_published_by_fkey FOREIGN KEY (published_by) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.event_purchase
    ADD CONSTRAINT event_purchase_event_discount_code_belongs_to_event_fkey FOREIGN KEY (event_id, event_discount_code_id) REFERENCES public.event_discount_code(event_id, event_discount_code_id);

ALTER TABLE ONLY public.event_purchase
    ADD CONSTRAINT event_purchase_event_discount_code_id_fkey FOREIGN KEY (event_discount_code_id) REFERENCES public.event_discount_code(event_discount_code_id);

ALTER TABLE ONLY public.event_purchase
    ADD CONSTRAINT event_purchase_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id);

ALTER TABLE ONLY public.event_purchase
    ADD CONSTRAINT event_purchase_event_ticket_type_belongs_to_event_fkey FOREIGN KEY (event_id, event_ticket_type_id) REFERENCES public.event_ticket_type(event_id, event_ticket_type_id);

ALTER TABLE ONLY public.event_purchase
    ADD CONSTRAINT event_purchase_event_ticket_type_id_fkey FOREIGN KEY (event_ticket_type_id) REFERENCES public.event_ticket_type(event_ticket_type_id);

ALTER TABLE ONLY public.event_purchase
    ADD CONSTRAINT event_purchase_payment_provider_id_fkey FOREIGN KEY (payment_provider_id) REFERENCES public.payment_provider(payment_provider_id);

ALTER TABLE ONLY public.event_purchase
    ADD CONSTRAINT event_purchase_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.event_refund_request
    ADD CONSTRAINT event_refund_request_event_purchase_id_fkey FOREIGN KEY (event_purchase_id) REFERENCES public.event_purchase(event_purchase_id);

ALTER TABLE ONLY public.event_refund_request
    ADD CONSTRAINT event_refund_request_requested_by_user_id_fkey FOREIGN KEY (requested_by_user_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.event_refund_request
    ADD CONSTRAINT event_refund_request_reviewed_by_user_id_fkey FOREIGN KEY (reviewed_by_user_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.event_series
    ADD CONSTRAINT event_series_created_by_fkey FOREIGN KEY (created_by) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.event_series
    ADD CONSTRAINT event_series_group_id_fkey FOREIGN KEY (group_id) REFERENCES public."group"(group_id);

ALTER TABLE ONLY public.event_speaker
    ADD CONSTRAINT event_speaker_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id);

ALTER TABLE ONLY public.event_speaker
    ADD CONSTRAINT event_speaker_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.event_sponsor
    ADD CONSTRAINT event_sponsor_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id);

ALTER TABLE ONLY public.event_sponsor
    ADD CONSTRAINT event_sponsor_group_sponsor_id_fkey FOREIGN KEY (group_sponsor_id) REFERENCES public.group_sponsor(group_sponsor_id);

ALTER TABLE ONLY public.event_ticket_price_window
    ADD CONSTRAINT event_ticket_price_window_event_ticket_type_id_fkey FOREIGN KEY (event_ticket_type_id) REFERENCES public.event_ticket_type(event_ticket_type_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.event_ticket_type
    ADD CONSTRAINT event_ticket_type_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.event_views
    ADD CONSTRAINT event_views_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id) ON DELETE SET NULL;

ALTER TABLE ONLY public.event_waitlist
    ADD CONSTRAINT event_waitlist_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id);

ALTER TABLE ONLY public.event_waitlist
    ADD CONSTRAINT event_waitlist_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public."group"
    ADD CONSTRAINT group_alliance_id_fkey FOREIGN KEY (alliance_id) REFERENCES public.alliance(alliance_id);

ALTER TABLE ONLY public.group_category
    ADD CONSTRAINT group_category_alliance_id_fkey FOREIGN KEY (alliance_id) REFERENCES public.alliance(alliance_id);

ALTER TABLE ONLY public."group"
    ADD CONSTRAINT group_group_category_id_fkey FOREIGN KEY (group_category_id) REFERENCES public.group_category(group_category_id);

ALTER TABLE ONLY public."group"
    ADD CONSTRAINT group_group_site_layout_id_fkey FOREIGN KEY (group_site_layout_id) REFERENCES public.group_site_layout(group_site_layout_id);

ALTER TABLE ONLY public.group_member
    ADD CONSTRAINT group_member_group_id_fkey FOREIGN KEY (group_id) REFERENCES public."group"(group_id);

ALTER TABLE ONLY public.group_member
    ADD CONSTRAINT group_member_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public."group"
    ADD CONSTRAINT group_region_id_fkey FOREIGN KEY (region_id) REFERENCES public.region(region_id);

ALTER TABLE ONLY public.group_role_group_permission
    ADD CONSTRAINT group_role_group_permission_group_permission_id_fkey FOREIGN KEY (group_permission_id) REFERENCES public.group_permission(group_permission_id);

ALTER TABLE ONLY public.group_role_group_permission
    ADD CONSTRAINT group_role_group_permission_group_role_id_fkey FOREIGN KEY (group_role_id) REFERENCES public.group_role(group_role_id);

ALTER TABLE ONLY public.group_sponsor
    ADD CONSTRAINT group_sponsor_group_id_fkey FOREIGN KEY (group_id) REFERENCES public."group"(group_id);

ALTER TABLE ONLY public.group_team
    ADD CONSTRAINT group_team_group_id_fkey FOREIGN KEY (group_id) REFERENCES public."group"(group_id);

ALTER TABLE ONLY public.group_team
    ADD CONSTRAINT group_team_role_fkey FOREIGN KEY (role) REFERENCES public.group_role(group_role_id);

ALTER TABLE ONLY public.group_team
    ADD CONSTRAINT group_team_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.group_views
    ADD CONSTRAINT group_views_group_id_fkey FOREIGN KEY (group_id) REFERENCES public."group"(group_id) ON DELETE SET NULL;

ALTER TABLE ONLY public.images
    ADD CONSTRAINT images_created_by_fkey FOREIGN KEY (created_by) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.legacy_event_host
    ADD CONSTRAINT legacy_event_host_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id);

ALTER TABLE ONLY public.legacy_event_speaker
    ADD CONSTRAINT legacy_event_speaker_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id);

ALTER TABLE ONLY public.meeting
    ADD CONSTRAINT meeting_auto_end_check_outcome_fk FOREIGN KEY (auto_end_check_outcome) REFERENCES public.meeting_auto_end_check_outcome(meeting_auto_end_check_outcome_id);

ALTER TABLE ONLY public.meeting
    ADD CONSTRAINT meeting_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id) ON DELETE SET NULL;

ALTER TABLE ONLY public.meeting
    ADD CONSTRAINT meeting_meeting_provider_id_fkey FOREIGN KEY (meeting_provider_id) REFERENCES public.meeting_provider(meeting_provider_id);

ALTER TABLE ONLY public.meeting
    ADD CONSTRAINT meeting_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.session(session_id) ON DELETE SET NULL;

ALTER TABLE ONLY public.notification_attachment
    ADD CONSTRAINT notification_attachment_attachment_id_fkey FOREIGN KEY (attachment_id) REFERENCES public.attachment(attachment_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.notification_attachment
    ADD CONSTRAINT notification_attachment_notification_id_fkey FOREIGN KEY (notification_id) REFERENCES public.notification(notification_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_kind_fkey FOREIGN KEY (kind) REFERENCES public.notification_kind(name) ON DELETE RESTRICT;

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_notification_template_data_id_fkey FOREIGN KEY (notification_template_data_id) REFERENCES public.notification_template_data(notification_template_data_id);

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(user_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.mentorship_request
    ADD CONSTRAINT mentorship_request_mentor_user_id_fkey FOREIGN KEY (mentor_user_id) REFERENCES public."user"(user_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.mentorship_request
    ADD CONSTRAINT mentorship_request_requester_user_id_fkey FOREIGN KEY (requester_user_id) REFERENCES public."user"(user_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.region
    ADD CONSTRAINT region_alliance_id_fkey FOREIGN KEY (alliance_id) REFERENCES public.alliance(alliance_id);

ALTER TABLE ONLY public.session
    ADD CONSTRAINT session_cfs_submission_id_fkey FOREIGN KEY (cfs_submission_id) REFERENCES public.cfs_submission(cfs_submission_id);

ALTER TABLE ONLY public.session
    ADD CONSTRAINT session_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.event(event_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.session
    ADD CONSTRAINT session_meeting_provider_id_fkey FOREIGN KEY (meeting_provider_id) REFERENCES public.meeting_provider(meeting_provider_id);

ALTER TABLE ONLY public.session_proposal
    ADD CONSTRAINT session_proposal_co_speaker_user_id_fkey FOREIGN KEY (co_speaker_user_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.session_proposal
    ADD CONSTRAINT session_proposal_session_proposal_level_id_fkey FOREIGN KEY (session_proposal_level_id) REFERENCES public.session_proposal_level(session_proposal_level_id);

ALTER TABLE ONLY public.session_proposal
    ADD CONSTRAINT session_proposal_session_proposal_status_id_fkey FOREIGN KEY (session_proposal_status_id) REFERENCES public.session_proposal_status(session_proposal_status_id);

ALTER TABLE ONLY public.session_proposal
    ADD CONSTRAINT session_proposal_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(user_id);

ALTER TABLE ONLY public.session
    ADD CONSTRAINT session_session_kind_id_fkey FOREIGN KEY (session_kind_id) REFERENCES public.session_kind(session_kind_id);

ALTER TABLE ONLY public.session_speaker
    ADD CONSTRAINT session_speaker_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.session(session_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.session_speaker
    ADD CONSTRAINT session_speaker_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(user_id);
