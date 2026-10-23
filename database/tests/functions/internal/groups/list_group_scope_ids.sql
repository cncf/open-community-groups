-- Tests listing the groups in a group's public scope.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'e4e40000-0000-0000-0000-000000000001'
\set groupCategoryID 'e4e40000-0000-0000-0000-000000000002'
\set hiddenTargetChildID 'e4e40000-0000-0000-0000-000000000003'
\set hiddenTargetGroupID 'e4e40000-0000-0000-0000-000000000004'
\set inactiveChildID 'e4e40000-0000-0000-0000-000000000005'
\set otherCommunityID 'e4e40000-0000-0000-0000-000000000006'
\set publicChildID 'e4e40000-0000-0000-0000-000000000007'
\set targetGroupID 'e4e40000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning every group
select fx_community(:'communityID');

-- Other community used to request the target group outside its community
select fx_community(:'otherCommunityID');

-- Group category for the community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Target group hidden after its public subgroup is linked
select fx_group(:'hiddenTargetGroupID', :'communityID', :'groupCategoryID');

-- Public target group
select fx_group(:'targetGroupID', :'communityID', :'groupCategoryID');

-- Public subgroup of the hidden target group
select fx_group(:'hiddenTargetChildID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'parent_group_id', :'hiddenTargetGroupID'
));

-- Inactive subgroup of the public target group
select fx_group(:'inactiveChildID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'parent_group_id', :'targetGroupID'
));

-- Public subgroup of the public target group
select fx_group(:'publicChildID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'parent_group_id', :'targetGroupID'
));

-- Hide the target group after linking its subgroup, because the parent trigger
-- rejects inactive parents on insert
update "group"
set active = false
where group_id = :'hiddenTargetGroupID';

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should exclude inactive subgroups
select is_empty(
    format(
        $$
        select s.group_id
        from list_group_scope_ids(%L::uuid, %L::uuid, true) s
        where s.group_id = %L::uuid
        $$,
        :'communityID',
        :'targetGroupID',
        :'inactiveChildID'
    ),
    'Should exclude inactive subgroups'
);

-- Should list only the target group when subgroups are excluded
select results_eq(
    format(
        $$
        select s.group_id
        from list_group_scope_ids(%L::uuid, %L::uuid, false) s
        $$,
        :'communityID',
        :'targetGroupID'
    ),
    format(
        $$ values (%L::uuid) $$,
        :'targetGroupID'
    ),
    'Should list only the target group when subgroups are excluded'
);

-- Should list the target group and its public subgroups
select set_eq(
    format(
        $$
        select s.group_id
        from list_group_scope_ids(%L::uuid, %L::uuid, true) s
        $$,
        :'communityID',
        :'targetGroupID'
    ),
    format(
        $$ values (%L::uuid), (%L::uuid) $$,
        :'publicChildID',
        :'targetGroupID'
    ),
    'Should list the target group and its public subgroups'
);

-- Should return an empty scope for a group outside the community
select is_empty(
    format(
        $$
        select s.group_id
        from list_group_scope_ids(%L::uuid, %L::uuid, true) s
        $$,
        :'otherCommunityID',
        :'targetGroupID'
    ),
    'Should return an empty scope for a group outside the community'
);

-- Should return an empty scope for a hidden target group
select is_empty(
    format(
        $$
        select s.group_id
        from list_group_scope_ids(%L::uuid, %L::uuid, true) s
        $$,
        :'communityID',
        :'hiddenTargetGroupID'
    ),
    'Should return an empty scope for a hidden target group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
