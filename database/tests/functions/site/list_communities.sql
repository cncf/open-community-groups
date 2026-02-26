-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set community3ID '00000000-0000-0000-0000-000000000003'
\set community4ID '00000000-0000-0000-0000-000000000004'
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

-- Communities
-- community1: Alpha Community - will have group and published event (should be included)
-- community2: Beta Community - will have group but no events (should be excluded)
-- community3: Gamma Community - will have no groups (should be excluded)
-- community4: Delta Community - inactive (should be excluded)
insert into community (
    community_id,
    active,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values
    (:'community1ID', true, 'https://example.com/alpha-banner_mobile.png', 'https://example.com/alpha-banner.png', 'First community', 'Alpha Community', 'https://example.com/alpha-logo.png', 'alpha-community'),
    (:'community2ID', true, 'https://example.com/beta-banner_mobile.png', 'https://example.com/beta-banner.png', 'Second community', 'Beta Community', 'https://example.com/beta-logo.png', 'beta-community'),
    (:'community3ID', true, 'https://example.com/gamma-banner_mobile.png', 'https://example.com/gamma-banner.png', 'Third community', 'Gamma Community', 'https://example.com/gamma-logo.png', 'gamma-community'),
    (:'community4ID', false, 'https://example.com/delta-banner_mobile.png', 'https://example.com/delta-banner.png', 'Fourth community', 'Delta Community', 'https://example.com/delta-logo.png', 'delta-community');

-- Group Categories
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategory1ID', :'community1ID', 'Technology'),
    (:'groupCategory2ID', :'community2ID', 'Technology');

-- Groups
insert into "group" (group_id, active, community_id, deleted, group_category_id, name, slug)
values
    (:'group1ID', true, :'community1ID', false, :'groupCategory1ID', 'Alpha Group', 'alpha-group'),
    (:'group2ID', true, :'community2ID', false, :'groupCategory2ID', 'Beta Group', 'beta-group');

-- Event Categories
insert into event_category (event_category_id, community_id, name)
values
    (:'eventCategory1ID', :'community1ID', 'Meetups'),
    (:'eventCategory2ID', :'community2ID', 'Meetups');

-- Events (only community1's group has a published event)
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

-- Should return only communities with at least one group and one published event
select is(
    list_communities()::jsonb,
    '[
        {
            "banner_mobile_url": "https://example.com/alpha-banner_mobile.png",
            "banner_url": "https://example.com/alpha-banner.png",
            "community_id": "00000000-0000-0000-0000-000000000001",
            "display_name": "Alpha Community",
            "logo_url": "https://example.com/alpha-logo.png",
            "name": "alpha-community"
        }
    ]'::jsonb,
    'Should return only communities with at least one group and one published event'
);

-- Should exclude communities with only deleted groups
update "group" set deleted = true, active = false where group_id = :'group1ID';
select is(
    list_communities()::jsonb,
    '[]'::jsonb,
    'Should exclude communities with only deleted groups'
);

-- Should exclude communities with only inactive groups
update "group" set deleted = false, active = false where group_id = :'group1ID';
select is(
    list_communities()::jsonb,
    '[]'::jsonb,
    'Should exclude communities with only inactive groups'
);

-- Should exclude communities with only canceled events
update "group" set active = true where group_id = :'group1ID';
update event set canceled = true, published = false where event_id = :'event1ID';
select is(
    list_communities()::jsonb,
    '[]'::jsonb,
    'Should exclude communities with only canceled events'
);

-- Should return empty array when no communities meet criteria
delete from event;
delete from "group";
select is(
    list_communities()::jsonb,
    '[]'::jsonb,
    'Should return empty array when no communities meet criteria'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
