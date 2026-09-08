-- Tests event-level external-payments readiness.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e0790000-0000-0000-0000-000000000001'
\set eventCategoryID 'e0790000-0000-0000-0000-000000000002'
\set eventID 'e0790000-0000-0000-0000-000000000003'
\set eventNoUrlID 'e0790000-0000-0000-0000-000000000008'
\set eventUnreadyID 'e0790000-0000-0000-0000-000000000004'
\set groupCategoryID 'e0790000-0000-0000-0000-000000000005'
\set groupID 'e0790000-0000-0000-0000-000000000006'
\set groupUnreadyID 'e0790000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Operator allowlist used by the ready-event scenario
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Community for readiness scenarios
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'external-ready-community',
    'External Ready Community',
    'Community for external readiness tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event category for readiness scenarios
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group category for readiness scenarios
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Allowlisted group with the external-payments toggle enabled
insert into "group" (
    country_code,
    community_id,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    'KR',
    :'communityID',
    true,
    :'groupCategoryID',
    :'groupID',
    'External Ready Group',
    'external-ready-group'
);

-- Group outside the allowlist
insert into "group" (
    country_code,
    community_id,
    external_payments_enabled,
    group_category_id,
    group_id,
    name,
    slug
) values (
    'US',
    :'communityID',
    true,
    :'groupCategoryID',
    :'groupUnreadyID',
    'External Unready Group',
    'external-unready-group'
);

-- External-marked event on the allowlisted group
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    external_payment_url,
    group_id,
    name,
    slug,
    timezone
) values (
    'Ready event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    'https://pay.example.test/ready',
    :'groupID',
    'Ready Event',
    'ready-event',
    'UTC'
);

-- Allowlisted event without an external payment URL
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone
) values (
    'No URL event',
    :'eventCategoryID',
    :'eventNoUrlID',
    'in-person',
    :'groupID',
    'No URL Event',
    'no-url-event',
    'UTC'
);

-- External-marked event on a group that is not allowlisted
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    external_payment_url,
    group_id,
    name,
    slug,
    timezone
) values (
    'Unready event',
    :'eventCategoryID',
    :'eventUnreadyID',
    'in-person',
    'https://pay.example.test/unready',
    :'groupUnreadyID',
    'Unready Event',
    'unready-event',
    'UTC'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report ready when the toggle, URL, and allowlist all match
select is(
    is_event_external_payments_ready(:'eventID'::uuid),
    true,
    'Should report ready when the toggle, URL, and allowlist all match'
);

-- Should report unready when the event has no external payment URL
select is(
    is_event_external_payments_ready(:'eventNoUrlID'::uuid),
    false,
    'Should report unready when the event has no external payment URL'
);

-- Should report unready when the group country is not allowlisted
select is(
    is_event_external_payments_ready(:'eventUnreadyID'::uuid),
    false,
    'Should report unready when the group country is not allowlisted'
);

-- Should report unready for an unknown event
select is(
    is_event_external_payments_ready('00000000-0000-0000-0000-000000000000'::uuid),
    false,
    'Should report unready for an unknown event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
