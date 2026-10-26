-- Tests event constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c00c0000-0000-0000-0000-000000000001'
\set eventCategoryID 'c00c0000-0000-0000-0000-000000000002'
\set eventDeletedID 'c00c0000-0000-0000-0000-000000000003'
\set eventEqualDatesID 'c00c0000-0000-0000-0000-000000000004'
\set eventInvalidDatesID 'c00c0000-0000-0000-0000-000000000005'
\set eventPublishedID 'c00c0000-0000-0000-0000-000000000006'
\set eventStartOnlyID 'c00c0000-0000-0000-0000-000000000007'
\set groupCategoryID 'c00c0000-0000-0000-0000-000000000008'
\set groupID 'c00c0000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the events
select fx_community(:'communityID');

-- Event category used by the events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the event group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Unpublished event deleted by the accepted deletion scenario
select fx_event(:'eventDeletedID', :'groupID', :'eventCategoryID');

-- Undated event given equal start and end dates
select fx_event(:'eventEqualDatesID', :'groupID', :'eventCategoryID');

-- Dated event receiving the rejected date ranges
select fx_event(:'eventInvalidDatesID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-01-01 12:00:00+00',
    'starts_at', '2030-01-01 10:00:00+00'
));

-- Published event receiving the rejected deletion
select fx_event(:'eventPublishedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', '2030-01-01 10:00:00+00'
));

-- Undated event given only a start date
select fx_event(:'eventStartOnlyID', :'groupID', :'eventCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept a deleted unpublished event
select lives_ok(
    format(
        $$update event set deleted = true where event_id = %L::uuid$$,
        :'eventDeletedID'
    ),
    'Should accept a deleted unpublished event'
);

-- Should accept ends_at equal to starts_at
select lives_ok(
    format(
        $$
            update event
            set
                ends_at = '2030-01-01 10:00:00+00',
                starts_at = '2030-01-01 10:00:00+00'
            where event_id = %L::uuid
        $$,
        :'eventEqualDatesID'
    ),
    'Should accept ends_at equal to starts_at'
);

-- Should accept starts_at without ends_at
select lives_ok(
    format(
        $$update event set starts_at = '2030-01-01 10:00:00+00' where event_id = %L::uuid$$,
        :'eventStartOnlyID'
    ),
    'Should accept starts_at without ends_at'
);

-- Should reject a deleted published event
select throws_ok(
    format(
        $$update event set deleted = true where event_id = %L::uuid$$,
        :'eventPublishedID'
    ),
    '23514',
    'new row for relation "event" violates check constraint "event_check"',
    'Should reject a deleted published event'
);

-- Should reject ends_at before starts_at
select throws_ok(
    format(
        $$update event set ends_at = '2030-01-01 09:00:00+00' where event_id = %L::uuid$$,
        :'eventInvalidDatesID'
    ),
    '23514',
    'new row for relation "event" violates check constraint "event_check2"',
    'Should reject ends_at before starts_at'
);

-- Should reject ends_at without starts_at
select throws_ok(
    format(
        $$update event set starts_at = null where event_id = %L::uuid$$,
        :'eventInvalidDatesID'
    ),
    '23514',
    'new row for relation "event" violates check constraint "event_check2"',
    'Should reject ends_at without starts_at'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
