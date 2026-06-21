-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance1ID '00000000-0000-0000-0000-000000000001'
\set alliance2ID '00000000-0000-0000-0000-000000000002'
\set alliance3ID '00000000-0000-0000-0000-000000000003'
\set alliance4ID '00000000-0000-0000-0000-000000000004'
\set event1ID '00000000-0000-0000-0000-000000000051'
\set event2ID '00000000-0000-0000-0000-000000000052'
\set eventCategory1ID '00000000-0000-0000-0000-000000000061'
\set eventCategory2ID '00000000-0000-0000-0000-000000000062'
\set group1ID '00000000-0000-0000-0000-000000000031'
\set group2ID '00000000-0000-0000-0000-000000000032'
\set groupCategory1ID '00000000-0000-0000-0000-000000000011'
\set groupCategory2ID '00000000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliances
-- alliance1: Alpha Alliance - will have group and published event (should be included)
-- alliance2: Beta Alliance - will have group but no events (should be excluded)
-- alliance3: Gamma Alliance - will have no groups (should be excluded)
-- alliance4: Delta Alliance - inactive (should be excluded)
insert into alliance (
    alliance_id,
    active,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values
    (:'alliance1ID', true, 'https://example.com/alpha-banner_mobile.png', 'https://example.com/alpha-banner.png', 'First alliance', 'Alpha Alliance', 'https://example.com/alpha-logo.png', 'alpha-alliance'),
    (:'alliance2ID', true, 'https://example.com/beta-banner_mobile.png', 'https://example.com/beta-banner.png', 'Second alliance', 'Beta Alliance', 'https://example.com/beta-logo.png', 'beta-alliance'),
    (:'alliance3ID', true, 'https://example.com/gamma-banner_mobile.png', 'https://example.com/gamma-banner.png', 'Third alliance', 'Gamma Alliance', 'https://example.com/gamma-logo.png', 'gamma-alliance'),
    (:'alliance4ID', false, 'https://example.com/delta-banner_mobile.png', 'https://example.com/delta-banner.png', 'Fourth alliance', 'Delta Alliance', 'https://example.com/delta-logo.png', 'delta-alliance');

-- Group Categories
insert into group_category (group_category_id, alliance_id, name)
values
    (:'groupCategory1ID', :'alliance1ID', 'Technology'),
    (:'groupCategory2ID', :'alliance2ID', 'Technology');

-- Groups
insert into "group" (group_id, active, alliance_id, deleted, group_category_id, name, slug)
values
    (:'group1ID', true, :'alliance1ID', false, :'groupCategory1ID', 'Alpha Group', 'alpha-group'),
    (:'group2ID', true, :'alliance2ID', false, :'groupCategory2ID', 'Beta Group', 'beta-group');

-- Event Categories
insert into event_category (event_category_id, alliance_id, name)
values
    (:'eventCategory1ID', :'alliance1ID', 'Meetups'),
    (:'eventCategory2ID', :'alliance2ID', 'Meetups');

-- Events (only alliance1's group has a published event)
insert into event (
    event_id,
    canceled,
    deleted,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    timezone
) values
    (:'event1ID', false, false, 'A published event', :'eventCategory1ID', 'in-person', :'group1ID', 'Alpha Event', true, 'alpha-event', 'America/Los_Angeles'),
    (:'event2ID', false, false, 'An unpublished event', :'eventCategory2ID', 'in-person', :'group2ID', 'Beta Event', false, 'beta-event', 'America/Los_Angeles');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return only alliances with at least one group and one published event
select is(
    list_alliances()::jsonb,
    '[
        {
            "banner_mobile_url": "https://example.com/alpha-banner_mobile.png",
            "banner_url": "https://example.com/alpha-banner.png",
            "alliance_id": "00000000-0000-0000-0000-000000000001",
            "display_name": "Alpha Alliance",
            "logo_url": "https://example.com/alpha-logo.png",
            "name": "alpha-alliance"
        }
    ]'::jsonb,
    'Should return only alliances with at least one group and one published event'
);

-- Should exclude alliances with only test events
update event set test_event = true where event_id = :'event1ID';
select is(
    list_alliances()::jsonb,
    '[]'::jsonb,
    'Should exclude alliances with only test events'
);
update event set test_event = false where event_id = :'event1ID';

-- Should exclude alliances with only deleted groups
update "group" set deleted = true, active = false where group_id = :'group1ID';
select is(
    list_alliances()::jsonb,
    '[]'::jsonb,
    'Should exclude alliances with only deleted groups'
);

-- Should exclude alliances with only inactive groups
update "group" set deleted = false, active = false where group_id = :'group1ID';
select is(
    list_alliances()::jsonb,
    '[]'::jsonb,
    'Should exclude alliances with only inactive groups'
);

-- Should exclude alliances with only canceled events
update "group" set active = true where group_id = :'group1ID';
update event set canceled = true, published = false where event_id = :'event1ID';
select is(
    list_alliances()::jsonb,
    '[]'::jsonb,
    'Should exclude alliances with only canceled events'
);

-- Should return empty array when no alliances meet criteria
delete from event;
delete from "group";
select is(
    list_alliances()::jsonb,
    '[]'::jsonb,
    'Should return empty array when no alliances meet criteria'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
