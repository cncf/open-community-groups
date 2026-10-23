-- Tests session constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c00d0000-0000-0000-0000-000000000001'
\set eventCategoryID 'c00d0000-0000-0000-0000-000000000002'
\set eventID 'c00d0000-0000-0000-0000-000000000003'
\set groupCategoryID 'c00d0000-0000-0000-0000-000000000004'
\set groupID 'c00d0000-0000-0000-0000-000000000005'
\set sessionEqualDatesID 'c00d0000-0000-0000-0000-000000000006'
\set sessionInvalidDatesID 'c00d0000-0000-0000-0000-000000000007'
\set sessionOpenEndedID 'c00d0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the event
select fx_community(:'communityID');

-- Event category used by the event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the event group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event without an end date, so the session bounds trigger skips its checks
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', '2030-01-01 10:00:00+00'
));

-- Session given equal start and end dates
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'sessionEqualDatesID', :'eventID', 'Equal Dates Session', 'in-person', '2030-01-01 10:00:00+00');

-- Session receiving the rejected date range
insert into session (session_id, event_id, name, session_kind_id, starts_at)
values (:'sessionInvalidDatesID', :'eventID', 'Invalid Dates Session', 'in-person', '2030-01-01 10:00:00+00');

-- Session whose end date is cleared
insert into session (session_id, event_id, name, session_kind_id, starts_at, ends_at)
values (
    :'sessionOpenEndedID',
    :'eventID',
    'Open Ended Session',
    'in-person',
    '2030-01-01 10:00:00+00',
    '2030-01-01 11:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept ends_at equal to starts_at
select lives_ok(
    format(
        $$update session set ends_at = '2030-01-01 10:00:00+00' where session_id = %L::uuid$$,
        :'sessionEqualDatesID'
    ),
    'Should accept ends_at equal to starts_at'
);

-- Should accept starts_at without ends_at
select lives_ok(
    format(
        $$update session set ends_at = null where session_id = %L::uuid$$,
        :'sessionOpenEndedID'
    ),
    'Should accept starts_at without ends_at'
);

-- Should reject ends_at before starts_at
select throws_ok(
    format(
        $$update session set ends_at = '2030-01-01 09:00:00+00' where session_id = %L::uuid$$,
        :'sessionInvalidDatesID'
    ),
    '23514',
    'new row for relation "session" violates check constraint "session_check"',
    'Should reject ends_at before starts_at'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
