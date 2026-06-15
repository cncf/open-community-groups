-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '9a070000-0000-0000-0000-000000000001'
\set community2ID '9a070000-0000-0000-0000-000000000002'
\set community3ID '9a070000-0000-0000-0000-000000000003'
\set community4ID '9a070000-0000-0000-0000-000000000004'
\set event1ID '9a070000-0000-0000-0000-000000000005'
\set event2ID '9a070000-0000-0000-0000-000000000006'
\set eventCategory1ID '9a070000-0000-0000-0000-000000000007'
\set eventCategory2ID '9a070000-0000-0000-0000-000000000008'
\set group1ID '9a070000-0000-0000-0000-000000000009'
\set group2ID '9a070000-0000-0000-0000-000000000010'
\set groupCategory1ID '9a070000-0000-0000-0000-000000000011'
\set groupCategory2ID '9a070000-0000-0000-0000-000000000012'

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
    name,
    display_name,
    description,
    active,
    banner_mobile_url,
    banner_url,
    logo_url
) values
    (
        :'community1ID',
        'alpha-community',
        'Alpha Community',
        'First community',
        true,
        'https://example.com/alpha-banner_mobile.png',
        'https://example.com/alpha-banner.png',
        'https://example.com/alpha-logo.png'
    ),
    (
        :'community2ID',
        'beta-community',
        'Beta Community',
        'Second community',
        true,
        'https://example.com/beta-banner_mobile.png',
        'https://example.com/beta-banner.png',
        'https://example.com/beta-logo.png'
    ),
    (
        :'community3ID',
        'gamma-community',
        'Gamma Community',
        'Third community',
        true,
        'https://example.com/gamma-banner_mobile.png',
        'https://example.com/gamma-banner.png',
        'https://example.com/gamma-logo.png'
    ),
    (
        :'community4ID',
        'delta-community',
        'Delta Community',
        'Fourth community',
        false,
        'https://example.com/delta-banner_mobile.png',
        'https://example.com/delta-banner.png',
        'https://example.com/delta-logo.png'
    );

-- Group category
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategory1ID', :'community1ID', 'Technology'),
    (:'groupCategory2ID', :'community2ID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values
    (:'eventCategory1ID', :'community1ID', 'Meetups'),
    (:'eventCategory2ID', :'community2ID', 'Meetups');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, active, deleted)
values
    (:'group1ID', :'community1ID', :'groupCategory1ID', 'Alpha Group', 'alpha-group', true, false),
    (:'group2ID', :'community2ID', :'groupCategory2ID', 'Beta Group', 'beta-group', true, false);

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
    (:'event1ID', false, false, 'A published event', :'eventCategory1ID',
        'in-person', :'group1ID', 'Alpha Event', true, 'alpha-event', 'America/Los_Angeles'),
    (:'event2ID', false, false, 'An unpublished event', :'eventCategory2ID',
        'in-person', :'group2ID', 'Beta Event', false, 'beta-event', 'America/Los_Angeles');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return only communities with at least one group and one published event
select is(
    list_communities()::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'banner_mobile_url', 'https://example.com/alpha-banner_mobile.png',
            'banner_url', 'https://example.com/alpha-banner.png',
            'community_id', :'community1ID',
            'display_name', 'Alpha Community',
            'logo_url', 'https://example.com/alpha-logo.png',
            'name', 'alpha-community'
        )
    ),
    'Should return only communities with at least one group and one published event'
);

-- Should exclude communities with only test events
update event set test_event = true where event_id = :'event1ID';
select is(
    list_communities()::jsonb,
    '[]'::jsonb,
    'Should exclude communities with only test events'
);
update event set test_event = false where event_id = :'event1ID';

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
