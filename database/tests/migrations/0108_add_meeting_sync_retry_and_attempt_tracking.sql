-- Tests the 0108 backfill of create-attempt and sticky host tracking columns.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set eventClaimedNoMeetingID '01080000-0000-0000-0000-000000000003'
\set eventDisabledAfterErrorID '01080000-0000-0000-0000-000000000012'
\set eventNotRequestedID '01080000-0000-0000-0000-000000000004'
\set eventWithMeetingID '01080000-0000-0000-0000-000000000005'
\set sessionClaimedNoMeetingID '01080000-0000-0000-0000-000000000010'
\set sessionOutOfBoundsID '01080000-0000-0000-0000-000000000013'
\set sessionWithMeetingID '01080000-0000-0000-0000-000000000011'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should backfill create-attempt and sticky host tracking for requested events without a meeting row
select results_eq(
    format(
        $$
            select
                meeting_create_attempted_at is not null,
                meeting_last_provider_host_user,
                meeting_sync_attempts
            from event
            where event_id = %L::uuid
        $$,
        :'eventClaimedNoMeetingID'
    ),
    $$ values (true, 'event-inflight-host@example.test', 0) $$,
    'Should backfill create-attempt and sticky host tracking for requested events without a meeting row'
);

-- Should leave unrequested events with null create-attempt and sticky host tracking
select results_eq(
    format(
        $$
            select
                meeting_create_attempted_at,
                meeting_last_provider_host_user,
                meeting_sync_attempts
            from event
            where event_id = %L::uuid
        $$,
        :'eventNotRequestedID'
    ),
    $$ values (null::timestamptz, null::text, 0) $$,
    'Should leave unrequested events with null create-attempt and sticky host tracking'
);

-- Should leave requested events that already have a meeting row with null create-attempt tracking
select results_eq(
    format(
        $$
            select
                meeting_create_attempted_at,
                meeting_last_provider_host_user,
                meeting_sync_attempts
            from event
            where event_id = %L::uuid
        $$,
        :'eventWithMeetingID'
    ),
    $$ values (null::timestamptz, null::text, 0) $$,
    'Should leave requested events that already have a meeting row with null create-attempt tracking'
);

-- Should backfill create-attempt and sticky host tracking for requested sessions without a meeting row
select results_eq(
    format(
        $$
            select
                meeting_create_attempted_at is not null,
                meeting_last_provider_host_user,
                meeting_sync_attempts
            from session
            where session_id = %L::uuid
        $$,
        :'sessionClaimedNoMeetingID'
    ),
    $$ values (true, 'session-inflight-host@example.test', 0) $$,
    'Should backfill create-attempt and sticky host tracking for requested sessions without a meeting row'
);

-- Should leave requested sessions that already have a meeting row with null create-attempt tracking
select results_eq(
    format(
        $$
            select
                meeting_create_attempted_at,
                meeting_last_provider_host_user,
                meeting_sync_attempts
            from session
            where session_id = %L::uuid
        $$,
        :'sessionWithMeetingID'
    ),
    $$ values (null::timestamptz, null::text, 0) $$,
    'Should leave requested sessions that already have a meeting row with null create-attempt tracking'
);

-- Should backfill create-attempt tracking for events disabled after a prior sync timeout
select results_eq(
    format(
        $$
            select
                meeting_create_attempted_at is not null,
                meeting_sync_attempts
            from event
            where event_id = %L::uuid
        $$,
        :'eventDisabledAfterErrorID'
    ),
    $$ values (true, 0) $$,
    'Should backfill create-attempt tracking for events disabled after a prior sync timeout'
);

-- Should backfill create-attempt tracking for legacy out-of-bounds sessions without aborting
select results_eq(
    format(
        $$
            select
                meeting_create_attempted_at is not null,
                meeting_sync_attempts
            from session
            where session_id = %L::uuid
        $$,
        :'sessionOutOfBoundsID'
    ),
    $$ values (true, 0) $$,
    'Should backfill create-attempt tracking for legacy out-of-bounds sessions without aborting'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
