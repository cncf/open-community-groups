-- Tests checking whether groups are publicly visible.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5ea10000-0000-0000-0000-000000000001'
\set deletedGroupID '5ea10000-0000-0000-0000-000000000002'
\set groupCategoryID '5ea10000-0000-0000-0000-000000000003'
\set groupID '5ea10000-0000-0000-0000-000000000004'
\set inactiveGroupID '5ea10000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the groups
select fx_community(:'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Active group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Deleted group, which the schema keeps inactive
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Inactive group
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept active groups
select is(
    (select is_group_public(g) from "group" g where g.group_id = :'groupID'),
    true,
    'Should accept active groups'
);

-- Should reject deleted groups
-- The schema keeps deleted groups inactive, so the row is flagged as active in
-- memory to isolate the deleted check
select is(
    (
        select is_group_public(jsonb_populate_record(g, '{"active": true}'))
        from "group" g
        where g.group_id = :'deletedGroupID'
    ),
    false,
    'Should reject deleted groups'
);

-- Should reject inactive groups
select is(
    (select is_group_public(g) from "group" g where g.group_id = :'inactiveGroupID'),
    false,
    'Should reject inactive groups'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
