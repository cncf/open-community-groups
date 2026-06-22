-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance2ID '5e070000-0000-0000-0000-000000000001'
\set allianceID '5e070000-0000-0000-0000-000000000002'
\set eventCategoryID '5e070000-0000-0000-0000-000000000003'
\set eventID '5e070000-0000-0000-0000-000000000004'
\set groupCategoryID '5e070000-0000-0000-0000-000000000005'
\set groupID '5e070000-0000-0000-0000-000000000006'
\set nonExistingEventID '5e070000-0000-0000-0000-000000000007'
\set ticketPriceWindowID '5e070000-0000-0000-0000-000000000008'
\set ticketTypeID '5e070000-0000-0000-0000-000000000009'
\set userID '5e070000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliances
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'event-summary-alliance',
    'Event Summary',
    'Alliance for summary tests',
    'https://example.test/banner-mobile.png',
    'https://example.test/banner.png',
    'https://example.test/logo.png'
), (
    :'alliance2ID',
    'other-alliance',
    'Other Alliance',
    'Another alliance',
    'https://example.test/other-banner-mobile.png',
    'https://example.test/other-banner.png',
    'https://example.test/other.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name, created_at)
values (:'groupCategoryID', :'allianceID', 'Event Category', '2025-01-01 00:00:00');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'Summary Events');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'userID', 'test_hash', 'summary-user@example.test', true, 'summary-user');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug, group_site_layout_id)
values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Summary Group',
    'summary-group',
    'default'
);

-- Event
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    timezone,
    venue_city,
    starts_at,
    capacity,
    published_at
) values (
    :'eventID',
    'Event summary test',
    :'eventCategoryID',
    'hybrid',
    :'groupID',
    'Summary Event',
    'USD',
    true,
    'summary-event',
    'America/New_York',
    'Metropolis',
    '2025-07-01 10:00:00+00',
    50,
    '2025-06-01 00:00:00+00'
);

-- Event ticket type
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketTypeID',
    :'eventID',
    1,
    50,
    'General admission'
);

-- Event ticket price window
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'ticketPriceWindowID',
    2500,
    :'ticketTypeID'
);

-- Event attendee
insert into event_attendee (event_id, user_id, checked_in, checked_in_at, created_at)
values (:'eventID', :'userID', true, '2025-06-02 00:00:00', '2025-06-02 00:00:00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the same payload as get_event_summary
select is(
    get_event_summary_by_id(:'allianceID'::uuid, :'eventID'::uuid)::jsonb,
    get_event_summary(:'allianceID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
    'Should return the same payload as get_event_summary'
);

-- Should return null for missing event
select ok(
    get_event_summary_by_id(:'allianceID'::uuid, :'nonExistingEventID'::uuid) is null,
    'Should return null when the event does not exist'
);

-- Should return null when alliance mismatches
select ok(
    get_event_summary_by_id(:'alliance2ID'::uuid, :'eventID'::uuid) is null,
    'Should return null when the event belongs to another alliance'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
