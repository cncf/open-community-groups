-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set meetingID '00000000-0000-0000-0000-000000000301'
\set missingMeetingID '00000000-0000-0000-0000-000000000302'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Zoom meeting row
insert into meeting (meeting_id, join_url, meeting_provider_id, provider_meeting_id)
values (:'meetingID', 'https://zoom.us/j/auto-end-check', 'zoom', 'auto-end-check');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should record auto_ended outcome
select lives_ok(
    format(
        $$select set_meeting_auto_end_check_outcome(%L::uuid, 'auto_ended')$$,
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

-- Should allow already_not_running outcome
select lives_ok(
    format(
        $$select set_meeting_auto_end_check_outcome(%L::uuid, 'already_not_running')$$,
        :'meetingID'
    ),
    'Should allow already_not_running outcome'
);
select is(
    (select auto_end_check_outcome from meeting where meeting_id = :'meetingID'),
    'already_not_running',
    'Should persist already_not_running outcome'
);

-- Should allow error outcome
select lives_ok(
    format(
        $$select set_meeting_auto_end_check_outcome(%L::uuid, 'error')$$,
        :'meetingID'
    ),
    'Should allow error outcome'
);
select is(
    (select auto_end_check_outcome from meeting where meeting_id = :'meetingID'),
    'error',
    'Should persist error outcome'
);

-- Should allow not_found outcome
select lives_ok(
    format(
        $$select set_meeting_auto_end_check_outcome(%L::uuid, 'not_found')$$,
        :'meetingID'
    ),
    'Should allow not_found outcome'
);
select is(
    (select auto_end_check_outcome from meeting where meeting_id = :'meetingID'),
    'not_found',
    'Should persist not_found outcome'
);

-- Should reject unsupported outcome
select throws_ok(
    format(
        $$select set_meeting_auto_end_check_outcome(%L::uuid, 'invalid')$$,
        :'meetingID'
    ),
    '23503',
    null,
    'Should reject unsupported auto end check outcomes'
);

-- Should not fail when meeting ID does not exist
select lives_ok(
    format(
        $$select set_meeting_auto_end_check_outcome(%L::uuid, 'auto_ended')$$,
        :'missingMeetingID'
    ),
    'Should not fail when meeting does not exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
