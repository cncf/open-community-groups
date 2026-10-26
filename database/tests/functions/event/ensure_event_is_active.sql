-- Tests validating that community events accept attendee enrollment.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community2ID '5e040000-0000-0000-0000-000000000001'
\set communityID '5e040000-0000-0000-0000-000000000002'
\set eventCanceledID '5e040000-0000-0000-0000-000000000003'
\set eventCategoryID '5e040000-0000-0000-0000-000000000004'
\set eventOKID '5e040000-0000-0000-0000-000000000007'
\set groupCategoryID '5e040000-0000-0000-0000-00000000000a'
\set groupID '5e040000-0000-0000-0000-00000000000b'
\set missingEventID '5e040000-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories and event categories
select fx_community(:'communityID');
select fx_community(:'community2ID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');

-- Active group hosting the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('slug', 'active-group'));

-- Published future event that accepts enrollment
select fx_event(:'eventOKID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Published canceled event rejected only by the enrollment predicate
select fx_event(:'eventCanceledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

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

-- Should reject event that no longer accepts enrollment
select throws_ok(
    format(
        $$select ensure_event_is_active(%L::uuid, %L::uuid)$$,
        :'communityID', :'eventCanceledID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject event that no longer accepts enrollment'
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
