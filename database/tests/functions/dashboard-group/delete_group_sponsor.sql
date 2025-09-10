-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '40000000-0000-0000-0000-000000000001'
\set groupID     '40000000-0000-0000-0000-000000000002'
\set sponsorID   '40000000-0000-0000-0000-000000000003'
\set eventID     '40000000-0000-0000-0000-000000000004'
\set categoryID  '40000000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'communityID',
    'cloud-native-london',
    'Cloud Native London',
    'london.cloudnative.org',
    'Cloud Native London Community',
    'Community for cloud native technologies in London',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Group Category (required by group)
insert into group_category (group_category_id, name, community_id)
values ('40000000-0000-0000-0000-000000000010', 'Tech', :'communityID');

-- Group
insert into "group" (group_id, community_id, name, slug, group_category_id)
values (:'groupID', :'communityID', 'Group London', 'group-london', '40000000-0000-0000-0000-000000000010');

-- Sponsor
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, level, website_url)
values (:'sponsorID', :'groupID', 'Kappa', 'https://ex.com/kappa.png', 'Silver', null);

-- Event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'categoryID', 'Conference', 'conference', :'communityID');

-- Event
insert into event (event_id, group_id, name, slug, description, timezone, event_category_id, event_kind_id)
values (
    :'eventID',
    :'groupID',
    'Event 1',
    'event-1',
    'desc',
    'UTC',
    :'categoryID',
    (select event_kind_id from event_kind limit 1)
);

-- Event references sponsor
insert into event_sponsor (event_id, group_sponsor_id)
values (:'eventID', :'sponsorID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: delete_group_sponsor fails when referenced by event_sponsor
select throws_like(
    $$select delete_group_sponsor('40000000-0000-0000-0000-000000000002'::uuid, '40000000-0000-0000-0000-000000000003'::uuid)$$,
    '%foreign key%',
    'delete_group_sponsor should fail when sponsor is referenced by event'
);

-- Remove reference and try again
delete from event_sponsor where group_sponsor_id = :'sponsorID'::uuid;

-- Test: delete_group_sponsor deletes the row when unreferenced
select lives_ok(
    $$select delete_group_sponsor('40000000-0000-0000-0000-000000000002'::uuid, '40000000-0000-0000-0000-000000000003'::uuid)$$,
    'delete_group_sponsor should not error when unreferenced'
);

select is(
    (select count(*) from group_sponsor where group_sponsor_id = '40000000-0000-0000-0000-000000000003'::uuid),
    0::bigint,
    'delete_group_sponsor should remove sponsor'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
