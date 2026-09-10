-- Tests locking active event cancellation targets.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeEventID 'd4060000-0000-0000-0000-000000000001'
\set canceledEventID 'd4060000-0000-0000-0000-000000000002'
\set communityID 'd4060000-0000-0000-0000-000000000003'
\set deletedEventID 'd4060000-0000-0000-0000-000000000004'
\set eventCategoryID 'd4060000-0000-0000-0000-000000000005'
\set groupCategoryID 'd4060000-0000-0000-0000-000000000006'
\set groupID 'd4060000-0000-0000-0000-000000000007'
\set missingEventID 'd4060000-0000-0000-0000-000000000008'
\set otherEventID 'd4060000-0000-0000-0000-000000000009'
\set otherGroupID 'd4060000-0000-0000-0000-000000000010'
\set pastEventID 'd4060000-0000-0000-0000-000000000011'
\set secondActiveEventID 'd4060000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the cancellation lock fixtures
select fx_community(:'communityID', jsonb_build_object(
    'description', 'Community',
    'display_name', 'Community Lock Events For Cancellation'
));

-- Event category shared by the cancellation lock events
select fx_event_category(:'eventCategoryID', :'communityID', jsonb_build_object('name', 'Events'));

-- Group category shared by the cancellation lock groups
select fx_group_category(:'groupCategoryID', :'communityID', jsonb_build_object('name', 'Groups'));

-- Baseline groups
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Groups used to verify cancellation lock ownership
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Group',
    'slug', 'group'
));

-- Events covering active, canceled, deleted, past, and cross-group targets
select fx_event(:'activeEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'Active',
    'ends_at', now() + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'name', 'Active',
    'slug', 'active',
    'starts_at', now() + interval '1 day'
));
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', now() + interval '2 days 1 hour',
    'event_kind_id', 'virtual',
    'slug', 'canceled',
    'starts_at', now() + interval '2 days'
));
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'deleted_at', current_timestamp,
    'ends_at', now() + interval '3 days 1 hour',
    'event_kind_id', 'virtual',
    'slug', 'deleted',
    'starts_at', now() + interval '3 days'
));
select fx_event(:'otherEventID', :'otherGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '4 days 1 hour',
    'event_kind_id', 'virtual',
    'slug', 'other',
    'starts_at', now() + interval '4 days'
));
select fx_event(:'pastEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '1 hour',
    'event_kind_id', 'virtual',
    'slug', 'past',
    'starts_at', now() - interval '2 hours'
));
select fx_event(:'secondActiveEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '5 days 1 hour',
    'event_kind_id', 'virtual',
    'starts_at', now() + interval '5 days'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should lock unique active targets regardless of input order
select lives_ok(
    format(
        $$select lock_events_for_cancellation(%L::uuid, array[%L::uuid, %L::uuid, %L::uuid])$$,
        :'groupID',
        :'secondActiveEventID',
        :'activeEventID',
        :'secondActiveEventID'
    ),
    'Should lock unique active targets regardless of input order'
);

-- Should reject a canceled target
select throws_ok(
    format(
        $$select lock_events_for_cancellation(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'canceledEventID'
    ),
    'OCG01',
    'one or more events were not found or inactive',
    'Should reject a canceled target'
);

-- Should reject a cross-group target
select throws_ok(
    format(
        $$select lock_events_for_cancellation(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'otherEventID'
    ),
    'OCG01',
    'one or more events were not found or inactive',
    'Should reject a cross-group target'
);

-- Should reject a deleted target
select throws_ok(
    format(
        $$select lock_events_for_cancellation(%L::uuid, array[%L::uuid])$$,
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
        $$select lock_events_for_cancellation(%L::uuid, '{}'::uuid[])$$,
        :'groupID'
    ),
    'event_ids cannot be empty',
    'Should reject an empty target list'
);

-- Should reject a missing target
select throws_ok(
    format(
        $$select lock_events_for_cancellation(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'missingEventID'
    ),
    'OCG01',
    'one or more events were not found or inactive',
    'Should reject a missing target'
);

-- Should reject a past target
select throws_ok(
    format(
        $$select lock_events_for_cancellation(%L::uuid, array[%L::uuid])$$,
        :'groupID',
        :'pastEventID'
    ),
    'OCG01',
    'one or more events were not found or inactive',
    'Should reject a past target'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
