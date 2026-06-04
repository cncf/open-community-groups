-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set meetingID '00000000-0000-0000-0000-000000001001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Claimed Zoom meeting row
insert into meeting (
    auto_end_check_claimed_at,
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id
) values (
    current_timestamp,
    'https://zoom.us/j/release-auto-end-claim',
    :'meetingID',
    'zoom',
    'release-auto-end-claim'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should not release the claim when the token does not match
select lives_ok(
    format(
        $$select release_meeting_auto_end_check_claim(current_timestamp - interval '1 hour', %L::uuid)$$,
        :'meetingID'
    ),
    'Should accept release with a mismatched claim token'
);
select isnt(
    (select auto_end_check_claimed_at from meeting where meeting_id = :'meetingID'),
    null,
    'Should keep claim when the claim token does not match'
);

-- Should release an auto-end claim with a matching token
select lives_ok(
    format(
        $$select release_meeting_auto_end_check_claim((select auto_end_check_claimed_at from meeting where meeting_id = %L::uuid), %L::uuid)$$,
        :'meetingID',
        :'meetingID'
    ),
    'Should release auto-end check claim'
);
select is(
    (select auto_end_check_claimed_at from meeting where meeting_id = :'meetingID'),
    null,
    'Should clear auto_end_check_claimed_at'
);
select isnt(
    (select updated_at from meeting where meeting_id = :'meetingID'),
    null,
    'Should update timestamp when releasing claim'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
