-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID '5e040000-0000-0000-0000-000000000001'
\set communityID '5e040000-0000-0000-0000-000000000002'
\set eventCanceledID '5e040000-0000-0000-0000-000000000003'
\set eventCategoryID '5e040000-0000-0000-0000-000000000004'
\set eventDeletedID '5e040000-0000-0000-0000-000000000005'
\set eventInactiveGroupID '5e040000-0000-0000-0000-000000000006'
\set eventOKID '5e040000-0000-0000-0000-000000000007'
\set eventPastID '5e040000-0000-0000-0000-000000000008'
\set eventUnpublishedID '5e040000-0000-0000-0000-000000000009'
\set groupCategoryID '5e040000-0000-0000-0000-00000000000a'
\set groupID '5e040000-0000-0000-0000-00000000000b'
\set inactiveGroupID '5e040000-0000-0000-0000-00000000000c'
\set missingEventID '5e040000-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories and event categories
select fx_community(:'communityID');
select fx_community(:'community2ID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');

-- Groups with scenario-specific state
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('slug', 'active-group'));
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'slug', 'inactive-group'
));

-- Events with scenario-specific state
select fx_event(:'eventOKID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'eventCanceledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'eventDeletedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'eventInactiveGroupID', :'inactiveGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event(:'eventPastID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp - interval '2 days'
));
select fx_event(:'eventUnpublishedID', :'groupID', :'eventCategoryID', jsonb_build_object('starts_at', current_timestamp + interval '1 day'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept active event
select lives_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'communityID', :'eventOKID'
    ),
    'Should accept active event'
);

-- Should reject missing event
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'communityID', :'missingEventID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject missing event'
);

-- Should reject event from another community
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'community2ID', :'eventOKID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject event from another community'
);

-- Should reject unpublished event
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'communityID', :'eventUnpublishedID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject unpublished event'
);

-- Should reject canceled event
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'communityID', :'eventCanceledID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject canceled event'
);

-- Should reject deleted event
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'communityID', :'eventDeletedID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject deleted event'
);

-- Should reject inactive-group event
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'communityID', :'eventInactiveGroupID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject inactive-group event'
);

-- Should reject past event
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'communityID', :'eventPastID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject past event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
