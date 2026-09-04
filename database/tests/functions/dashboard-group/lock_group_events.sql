-- Tests locking a group and its event mutation targets.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeEventID 'd4070000-0000-0000-0000-000000000001'
\set communityID 'd4070000-0000-0000-0000-000000000002'
\set deletedEventID 'd4070000-0000-0000-0000-000000000003'
\set deletedGroupID 'd4070000-0000-0000-0000-000000000012'
\set eventCategoryID 'd4070000-0000-0000-0000-000000000004'
\set groupCategoryID 'd4070000-0000-0000-0000-000000000005'
\set groupID 'd4070000-0000-0000-0000-000000000006'
\set missingEventID 'd4070000-0000-0000-0000-000000000007'
\set missingGroupID 'd4070000-0000-0000-0000-000000000008'
\set otherEventID 'd4070000-0000-0000-0000-000000000009'
\set otherGroupID 'd4070000-0000-0000-0000-000000000010'
\set secondActiveEventID 'd4070000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the group event lock fixtures
select fx_community(:'communityID', jsonb_build_object(
    'description', 'Community',
    'display_name', 'Community Lock Group Events'
));

-- Event category shared by the group event lock targets
select fx_event_category(:'eventCategoryID', :'communityID', jsonb_build_object('name', 'Events'));

-- Group category shared by the group event lock owners
select fx_group_category(:'groupCategoryID', :'communityID', jsonb_build_object('name', 'Groups'));

-- Baseline groups
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Groups used to verify event ownership
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Group',
    'slug', 'group'
));

-- Deleted group rejected as an inactive event owner
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Events covering active, deleted, and cross-group targets
select fx_event(:'activeEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'Active',
    'event_kind_id', 'virtual',
    'name', 'Active',
    'slug', 'active'
));
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'deleted_at', current_timestamp,
    'description', 'Deleted',
    'event_kind_id', 'virtual',
    'name', 'Deleted',
    'slug', 'deleted'
));
select fx_event(:'otherEventID', :'otherGroupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'slug', 'other'
));
select fx_event(:'secondActiveEventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should lock unique active targets regardless of input order
select lives_ok(
    format(
        $$select lock_group_events(%L::uuid, array[%L::uuid, %L::uuid, %L::uuid])$$,
        :'groupID',
        :'secondActiveEventID',
        :'activeEventID',
        :'secondActiveEventID'
    ),
    'Should lock unique active targets regardless of input order'
);

-- Should reject a cross-group target
select throws_ok(
    format(
        $$select lock_group_events(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'otherEventID'
    ),
    'OCG01',
    'one or more events were not found or inactive',
    'Should reject a cross-group target'
);

-- Should reject a deleted group
select throws_ok(
    format(
        $$select lock_group_events(%L::uuid, array[%L::uuid])$$,
        :'deletedGroupID',
        :'activeEventID'
    ),
    'OCG01',
    'group not found or inactive',
    'Should reject a deleted group'
);

-- Should reject a deleted target
select throws_ok(
    format(
        $$select lock_group_events(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'deletedEventID'
    ),
    'OCG01',
    'one or more events were not found or inactive',
    'Should reject a deleted target'
);

-- Should reject an empty target list
select throws_ok(
    format(
        $$select lock_group_events(%L::uuid, '{}'::uuid[])$$,
        :'groupID'
    ),
    'event_ids cannot be empty',
    'Should reject an empty target list'
);

-- Should reject a missing group
select throws_ok(
    format(
        $$select lock_group_events(%L::uuid, array[%L::uuid])$$,
        :'missingGroupID',
        :'activeEventID'
    ),
    'OCG01',
    'group not found or inactive',
    'Should reject a missing group'
);

-- Should reject a missing target
select throws_ok(
    format(
        $$select lock_group_events(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'missingEventID'
    ),
    'OCG01',
    'one or more events were not found or inactive',
    'Should reject a missing target'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
