-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set meetingID '7a0d0000-0000-0000-0000-000000000001'
\set missingMeetingID '7a0d0000-0000-0000-0000-000000000002'

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
    'https://zoom.us/j/auto-end-check',
    :'meetingID',
    'zoom',
    'auto-end-check'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should not record outcome when the claim token does not match
select lives_ok(
    format(
        $$select set_meeting_auto_end_check_outcome(current_timestamp - interval '1 hour', %L::uuid, 'auto_ended')$$,
        :'meetingID'
    ),
    'Should accept outcome with a mismatched claim token'
);
select results_eq(
    format(
        $query$
        select
            auto_end_check_at,
            auto_end_check_outcome
        from meeting
        where meeting_id = %L::uuid
        $query$,
        :'meetingID'
    ),
    $expected$
    values (
        null::timestamptz,
        null::text
    )
    $expected$,
    'Should keep outcome unset when the claim token does not match'
);

-- Should record auto_ended outcome with a matching token
select lives_ok(
    format(
        $$select set_meeting_auto_end_check_outcome((select auto_end_check_claimed_at from meeting where meeting_id = %L::uuid), %L::uuid, 'auto_ended')$$,
        :'meetingID',
        :'meetingID'
    ),
    'Should record auto_ended outcome'
);
select isnt(
    (select auto_end_check_at from meeting where meeting_id = :'meetingID'),
    null,
    'Should set auto_end_check_at when writing auto_ended'
);
select is(
    (select auto_end_check_outcome from meeting where meeting_id = :'meetingID'),
    'auto_ended',
    'Should persist auto_ended outcome'
);
select is(
    (select auto_end_check_claimed_at from meeting where meeting_id = :'meetingID'),
    null,
    'Should clear auto-end check claim when writing auto_ended'
);

-- Reclaim meeting for next outcome
update meeting
set auto_end_check_at = null,
    auto_end_check_claimed_at = current_timestamp,
    auto_end_check_outcome = null
where meeting_id = :'meetingID';

-- Should allow already_not_running outcome
select lives_ok(
    format(
        $$select set_meeting_auto_end_check_outcome((select auto_end_check_claimed_at from meeting where meeting_id = %L::uuid), %L::uuid, 'already_not_running')$$,
        :'meetingID',
        :'meetingID'
    ),
    'Should allow already_not_running outcome'
);
select is(
    (select auto_end_check_outcome from meeting where meeting_id = :'meetingID'),
    'already_not_running',
    'Should persist already_not_running outcome'
);

-- Reclaim meeting for next outcome
update meeting
set auto_end_check_at = null,
    auto_end_check_claimed_at = current_timestamp,
    auto_end_check_outcome = null
where meeting_id = :'meetingID';

-- Should allow error outcome
select lives_ok(
    format(
        $$select set_meeting_auto_end_check_outcome((select auto_end_check_claimed_at from meeting where meeting_id = %L::uuid), %L::uuid, 'error')$$,
        :'meetingID',
        :'meetingID'
    ),
    'Should allow error outcome'
);
select is(
    (select auto_end_check_outcome from meeting where meeting_id = :'meetingID'),
    'error',
    'Should persist error outcome'
);

-- Reclaim meeting for next outcome
update meeting
set auto_end_check_at = null,
    auto_end_check_claimed_at = current_timestamp,
    auto_end_check_outcome = null
where meeting_id = :'meetingID';

-- Should allow not_found outcome
select lives_ok(
    format(
        $$select set_meeting_auto_end_check_outcome((select auto_end_check_claimed_at from meeting where meeting_id = %L::uuid), %L::uuid, 'not_found')$$,
        :'meetingID',
        :'meetingID'
    ),
    'Should allow not_found outcome'
);
select is(
    (select auto_end_check_outcome from meeting where meeting_id = :'meetingID'),
    'not_found',
    'Should persist not_found outcome'
);

-- Reclaim meeting for next outcome
update meeting
set auto_end_check_at = null,
    auto_end_check_claimed_at = current_timestamp,
    auto_end_check_outcome = null
where meeting_id = :'meetingID';

-- Should reject unsupported outcome
select throws_ok(
    format(
        $$select set_meeting_auto_end_check_outcome((select auto_end_check_claimed_at from meeting where meeting_id = %L::uuid), %L::uuid, 'invalid')$$,
        :'meetingID',
        :'meetingID'
    ),
    '23503',
    null,
    'Should reject unsupported auto end check outcomes'
);

-- Should not fail when meeting ID does not exist
select lives_ok(
    format(
        $$select set_meeting_auto_end_check_outcome(current_timestamp, %L::uuid, 'auto_ended')$$,
        :'missingMeetingID'
    ),
    'Should not fail when meeting does not exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
