-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '7a0e0000-0000-0000-0000-000000000001'
\set eventCategoryID '7a0e0000-0000-0000-0000-000000000002'
\set eventID '7a0e0000-0000-0000-0000-000000000003'
\set eventStaleClaimID '7a0e0000-0000-0000-0000-000000000004'
\set groupCategoryID '7a0e0000-0000-0000-0000-000000000005'
\set groupID '7a0e0000-0000-0000-0000-000000000006'
\set orphanMeetingID '7a0e0000-0000-0000-0000-000000000007'
\set sessionID '7a0e0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event with scenario-specific state
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'event-claim-host@example.com',
    'meeting_sync_claimed_at', current_timestamp,
    'timezone', 'America/New_York'
));

-- Event with stale claim
select fx_event(:'eventStaleClaimID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'meeting_error', 'Previous sync error',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'event-stale-claim-host@example.com',
    'meeting_sync_claimed_at', current_timestamp,
    'timezone', 'America/New_York'
));

-- Session
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_sync_claimed_at,
    starts_at
) values (
    :'sessionID',
    :'eventID',
    'Test Session',
    'virtual',
    false,
    'session-claim-host@example.com',
    current_timestamp,
    '2025-06-01 10:00:00-04'
);

-- Orphan meeting claimed for deletion
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,
    sync_claimed_at
) values (
    :'orphanMeetingID',
    'https://zoom.us/j/provider-001',
    'zoom',
    'provider-001',
    current_timestamp
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should set event error and sync flag for event meeting
select lives_ok(
    format(
        $$select set_meeting_error(%L::text, %L::uuid, null, null, (select meeting_sync_claimed_at from event where event_id = %L::uuid), get_event_meeting_sync_state_hash(%L::uuid))$$,
        'event sync failed',
        :'eventID',
        :'eventID',
        :'eventID'
    ),
    'Should set event error and sync flag for event meeting'
);
select is(
    (select meeting_error from event where event_id = :'eventID'),
    'event sync failed',
    'Should persist event meeting_error'
);
select results_eq(
    format(
        $query$
        select
            meeting_in_sync,
            meeting_provider_host_user,
            meeting_sync_claimed_at
        from event
        where event_id = %L::uuid
        $query$,
        :'eventID'
    ),
    $expected$
    values (
        true,
        null::text,
        null::timestamptz
    )
    $expected$,
    'Should mark event as in sync and clear claim'
);

-- Should not set event error as current when owner state changed after claim
select lives_ok(
    format(
        $sql$
        with claimed as (
            select
                get_event_meeting_sync_state_hash(event_id) as sync_state_hash,
                meeting_sync_claimed_at
            from event
            where event_id = %L::uuid
        ),
        changed as (
            update event
            set name = 'Event Changed After Claim'
            where event_id = %L::uuid
            returning event_id
        )
        select set_meeting_error(
            'new sync failure',
            %L,
            null,
            null,
            claimed.meeting_sync_claimed_at,
            claimed.sync_state_hash
        )
        from claimed, changed
        $sql$,
        :'eventStaleClaimID',
        :'eventStaleClaimID',
        :'eventStaleClaimID'
    ),
    'Should complete error path for stale event claim'
);
select is(
    (select meeting_error from event where event_id = :'eventStaleClaimID'),
    'Previous sync error',
    'Should preserve previous event meeting_error when claim is stale'
);
select results_eq(
    format(
        $query$
        select
            meeting_in_sync,
            meeting_provider_host_user,
            meeting_sync_claimed_at
        from event
        where event_id = %L::uuid
        $query$,
        :'eventStaleClaimID'
    ),
    $expected$
    values (
        false,
        null::text,
        null::timestamptz
    )
    $expected$,
    'Event changed after error claim remains out of sync'
);

-- Should set session error and sync flag for session meeting
select lives_ok(
    format(
        $$select set_meeting_error(%L::text, null, null, %L::uuid, (select meeting_sync_claimed_at from session where session_id = %L::uuid), get_session_meeting_sync_state_hash(%L::uuid))$$,
        'session sync failed',
        :'sessionID',
        :'sessionID',
        :'sessionID'
    ),
    'Should set session error and sync flag for session meeting'
);
select is(
    (select meeting_error from session where session_id = :'sessionID'),
    'session sync failed',
    'Should persist session meeting_error'
);
select results_eq(
    format(
        $query$
        select
            meeting_in_sync,
            meeting_provider_host_user,
            meeting_sync_claimed_at
        from session
        where session_id = %L::uuid
        $query$,
        :'sessionID'
    ),
    $expected$
    values (
        true,
        null::text,
        null::timestamptz
    )
    $expected$,
    'Should mark session as in sync and clear claim'
);

-- Should not delete orphan meeting when the claim token does not match
select lives_ok(
    format(
        $$select set_meeting_error(%L::text, null, %L::uuid, null, current_timestamp - interval '1 hour', null)$$,
        'orphan sync failed',
        :'orphanMeetingID'
    ),
    'Should accept orphan error with a mismatched claim token'
);
select is(
    (select count(*) from meeting where meeting_id = :'orphanMeetingID'),
    1::bigint,
    'Should keep orphan meeting when claim token does not match'
);

-- Should delete orphan meeting when no event/session exists
select lives_ok(
    format(
        $$select set_meeting_error(%L::text, null, %L::uuid, null, (select sync_claimed_at from meeting where meeting_id = %L::uuid), null)$$,
        'orphan sync failed',
        :'orphanMeetingID',
        :'orphanMeetingID'
    ),
    'Should delete orphan meeting when no event/session exists'
);
select is(
    (select count(*) from meeting where meeting_id = :'orphanMeetingID'),
    0::bigint,
    'Should remove orphan meeting record'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
