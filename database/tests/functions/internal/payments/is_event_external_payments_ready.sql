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

-- Baseline communities, group categories and event categories
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');

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

-- Allowlisted group with the external-payments toggle enabled
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true
));

-- Group outside the allowlist
select fx_group(:'groupUnreadyID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'US',
    'external_payments_enabled', true
));

-- Event without an external payment URL
select fx_event(:'eventNoUrlID', :'groupID', :'eventCategoryID');

-- External-marked event on the allowlisted group
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/ready',
    'slug', 'ready-event'
));

-- External-marked event on a group that is not allowlisted
select fx_event(:'eventUnreadyID', :'groupUnreadyID', :'eventCategoryID', jsonb_build_object('external_payment_url', 'https://pay.example.test/unready'));

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
