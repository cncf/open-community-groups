-- Tests meeting constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set meetingID 'c0100000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Orphan meeting receiving sync attempt constraint checks
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id
) values (
    :'meetingID',
    'https://zoom.us/j/meeting-constraints-001',
    'zoom',
    'meeting-constraints-001'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept zero sync attempts
select lives_ok(
    format(
        $$update meeting set sync_attempts = 0 where meeting_id = %L::uuid$$,
        :'meetingID'
    ),
    'Should accept zero sync attempts'
);

-- Should reject negative sync attempts
select throws_ok(
    format(
        $$update meeting set sync_attempts = -1 where meeting_id = %L::uuid$$,
        :'meetingID'
    ),
    '23514',
    'new row for relation "meeting" violates check constraint "meeting_sync_attempts_check"',
    'Should reject negative sync attempts'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
