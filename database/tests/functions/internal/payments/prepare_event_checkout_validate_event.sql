-- Tests locking and validating events before checkout.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79270000-0000-0000-0000-000000000001'
\set eventCategoryID '79270000-0000-0000-0000-000000000002'
\set groupCategoryID '79270000-0000-0000-0000-000000000003'
\set groupID '79270000-0000-0000-0000-000000000004'
\set otherCommunityID '79270000-0000-0000-0000-000000000005'
\set unpublishedEventID '79270000-0000-0000-0000-000000000006'
\set validEventID '79270000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, categories and group
select fx_community(:'communityID');
select fx_community(:'otherCommunityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Unpublished upcoming event rejected because checkout requires publication
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', false,
    'starts_at', now() + interval '1 day'
));

-- Published upcoming event open to checkout
select fx_event(:'validEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the locked event row
select is(
    (prepare_event_checkout_validate_event(:'communityID'::uuid, :'validEventID'::uuid)).event_id,
    :'validEventID'::uuid,
    'Should return the locked event row'
);

-- Should reject unpublished events
select throws_ok(
    format(
        $$select prepare_event_checkout_validate_event(%L::uuid, %L::uuid)$$,
        :'communityID',
        :'unpublishedEventID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject unpublished events'
);

-- Should reject events from another community
select throws_ok(
    format(
        $$select prepare_event_checkout_validate_event(%L::uuid, %L::uuid)$$,
        :'otherCommunityID',
        :'validEventID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject events from another community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
