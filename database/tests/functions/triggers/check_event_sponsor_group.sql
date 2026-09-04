-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ab030000-0000-0000-0000-000000000001'
\set eventCategoryID 'ab030000-0000-0000-0000-000000000002'
\set eventID 'ab030000-0000-0000-0000-000000000003'
\set group1CategoryID 'ab030000-0000-0000-0000-000000000004'
\set group1ID 'ab030000-0000-0000-0000-000000000005'
\set group2CategoryID 'ab030000-0000-0000-0000-000000000006'
\set group2ID 'ab030000-0000-0000-0000-000000000007'
\set sponsor1ID 'ab030000-0000-0000-0000-000000000008'
\set sponsor2ID 'ab030000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, event categories, groups and events
select fx_community(:'communityID');
select fx_group_category(:'group1CategoryID', :'communityID');
select fx_group_category(:'group2CategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'group1ID', :'communityID', :'group1CategoryID');
select fx_group(:'group2ID', :'communityID', :'group2CategoryID');
select fx_event(:'eventID', :'group1ID', :'eventCategoryID');

-- Sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url) values
    (:'sponsor1ID', :'group1ID', 'Sponsor 1', 'https://example.com/sponsor1.png'),
    (:'sponsor2ID', :'group2ID', 'Sponsor 2', 'https://example.com/sponsor2.png');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when sponsor is from same group as event
select lives_ok(
    format('insert into event_sponsor (event_id, group_sponsor_id, level) values (%L, %L, ''Gold'')', :'eventID', :'sponsor1ID'),
    'Should succeed when sponsor is from same group as event'
);

-- Should fail when sponsor is from different group
select throws_ok(
    format('insert into event_sponsor (event_id, group_sponsor_id, level) values (%L, %L, ''Gold'')', :'eventID', :'sponsor2ID'),
    'OCG01',
    'sponsor not found in group',
    'Should fail when sponsor is from different group'
);

-- Should fail when updating event_sponsor to sponsor from different group
select throws_ok(
    format('update event_sponsor set group_sponsor_id = %L where event_id = %L', :'sponsor2ID', :'eventID'),
    'OCG01',
    'sponsor not found in group',
    'Should fail when updating event_sponsor to sponsor from different group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
