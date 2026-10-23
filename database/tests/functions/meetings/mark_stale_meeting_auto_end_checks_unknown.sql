-- Tests marking stale meeting auto-end check claims as unknown.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set meetingCheckedID '7a090000-0000-0000-0000-000000000002'
\set meetingFreshID '7a090000-0000-0000-0000-000000000003'
\set meetingID '7a090000-0000-0000-0000-000000000001'

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

-- Stale claimed Zoom meeting row whose auto-end check already has an outcome
insert into meeting (
    auto_end_check_at,
    auto_end_check_claimed_at,
    auto_end_check_outcome,
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id
) values (
    '2026-06-01 10:00:00+00',
    current_timestamp - interval '30 minutes',
    'auto_ended',
    'https://zoom.us/j/checked-auto-end-claim',
    :'meetingCheckedID',
    'zoom',
    'checked-auto-end-claim'
);

-- Zoom meeting row claimed within the processing timeout
insert into meeting (
    auto_end_check_claimed_at,
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id
) values (
    current_timestamp - interval '1 minute',
    'https://zoom.us/j/fresh-auto-end-claim',
    :'meetingFreshID',
    'zoom',
    'fresh-auto-end-claim'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject non-positive processing timeouts
select throws_ok(
    $$select mark_stale_meeting_auto_end_checks_unknown(0)$$,
    'P0001',
    'processing timeout must be positive',
    'Should reject non-positive processing timeouts'
);

-- Should mark one stale auto-end claim
select is(
    mark_stale_meeting_auto_end_checks_unknown(900),
    1,
    'Should mark one stale auto-end claim'
);

-- Should store the unknown outcome and release the stale claim
select results_eq(
    format(
        $query$
        select
            auto_end_check_at,
            auto_end_check_claimed_at,
            auto_end_check_outcome,
            updated_at
        from meeting
        where meeting_id = %L::uuid
        $query$,
        :'meetingID'
    ),
    $expected$
    values (
        current_timestamp,
        null::timestamptz,
        'error'::text,
        current_timestamp
    )
    $expected$,
    'Should store the unknown outcome and release the stale claim'
);

-- Should keep the stale claim on a meeting whose auto-end check has an outcome
select results_eq(
    format(
        $query$
        select
            auto_end_check_at,
            auto_end_check_claimed_at,
            auto_end_check_outcome,
            updated_at
        from meeting
        where meeting_id = %L::uuid
        $query$,
        :'meetingCheckedID'
    ),
    $expected$
    values (
        '2026-06-01 10:00:00+00'::timestamptz,
        current_timestamp - interval '30 minutes',
        'auto_ended'::text,
        null::timestamptz
    )
    $expected$,
    'Should keep the stale claim on a meeting whose auto-end check has an outcome'
);

-- Should keep the auto-end claim made within the processing timeout
select results_eq(
    format(
        $query$
        select
            auto_end_check_at,
            auto_end_check_claimed_at,
            auto_end_check_outcome,
            updated_at
        from meeting
        where meeting_id = %L::uuid
        $query$,
        :'meetingFreshID'
    ),
    $expected$
    values (
        null::timestamptz,
        current_timestamp - interval '1 minute',
        null::text,
        null::timestamptz
    )
    $expected$,
    'Should keep the auto-end claim made within the processing timeout'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
