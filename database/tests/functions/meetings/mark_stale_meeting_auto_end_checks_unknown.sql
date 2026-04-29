-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set meetingID '00000000-0000-0000-0000-000000001101'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Stale claimed Zoom meeting row
insert into meeting (
    auto_end_check_claimed_at,
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id
) values (
    current_timestamp - interval '30 minutes',
    'https://zoom.us/j/stale-auto-end-claim',
    :'meetingID',
    'zoom',
    'stale-auto-end-claim'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should mark stale auto-end claims unknown
select is(
    mark_stale_meeting_auto_end_checks_unknown(900),
    1,
    'Should mark one stale auto-end claim'
);
select isnt(
    (select auto_end_check_at from meeting where meeting_id = :'meetingID'),
    null,
    'Should set auto_end_check_at'
);
select is(
    (select auto_end_check_claimed_at from meeting where meeting_id = :'meetingID'),
    null,
    'Should clear auto_end_check_claimed_at'
);
select is(
    (select auto_end_check_outcome from meeting where meeting_id = :'meetingID'),
    'error',
    'Should store unknown auto-end outcome as error'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
