-- Tests releasing retryable meeting sync claims with optional backoff delays.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(25);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '7a0c0000-0000-0000-0000-000000000001'
\set eventCategoryID '7a0c0000-0000-0000-0000-000000000002'
\set eventEditedDuringClaimID '7a0c0000-0000-0000-0000-000000000011'
\set eventID '7a0c0000-0000-0000-0000-000000000003'
\set eventNoDelayID '7a0c0000-0000-0000-0000-000000000010'
\set groupCategoryID '7a0c0000-0000-0000-0000-000000000004'
\set groupID '7a0c0000-0000-0000-0000-000000000005'
\set keptEventID '7a0c0000-0000-0000-0000-000000000008'
\set keptSessionID '7a0c0000-0000-0000-0000-000000000009'
\set meetingID '7a0c0000-0000-0000-0000-000000000006'
\set sessionID '7a0c0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and group
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Claimed event meeting
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2026-06-01 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_create_attempted_at', current_timestamp - interval '5 minutes',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'host@example.com',
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'meeting_sync_attempts', 2,
    'meeting_sync_claimed_at', current_timestamp,
    'published', true,
    'starts_at', '2026-06-01 10:00:00+00'
));

-- Claimed event without active host reservation, carrying an earlier sticky host and released without delay
select fx_event(:'eventNoDelayID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2026-06-02 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_create_attempted_at', current_timestamp - interval '5 minutes',
    'meeting_in_sync', false,
    'meeting_last_provider_host_user', 'prior-host@example.com',
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'meeting_sync_attempts', 3,
    'meeting_sync_claimed_at', current_timestamp,
    'published', true,
    'starts_at', '2026-06-02 10:00:00+00'
));

-- Claimed event whose provider-visible state changed while claimed
select fx_event(:'eventEditedDuringClaimID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2026-06-03 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_create_attempted_at', current_timestamp - interval '5 minutes',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'edited-claim-host@example.com',
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'meeting_sync_attempts', 9,
    'meeting_sync_claimed_at', current_timestamp,
    'published', true,
    'starts_at', '2026-06-03 10:00:00+00'
));

-- Claimed event meeting marked keep (null) while claimed
select fx_event(:'keptEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2026-06-01 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_in_sync', null,
    'meeting_provider_host_user', 'kept-host@example.com',
    'meeting_provider_id', 'zoom',
    'meeting_requested', null,
    'meeting_sync_attempts', 4,
    'meeting_sync_claimed_at', current_timestamp,
    'published', true,
    'starts_at', '2026-06-01 10:00:00+00'
));

-- Claimed orphan meeting
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,
    sync_claimed_at
) values (
    :'meetingID',
    'https://zoom.us/j/orphan-release-meeting-sync-claim',
    'zoom',
    'orphan-release-meeting-sync-claim',
    current_timestamp
);

-- Claimed session meeting
insert into session (
    session_id,
    event_id,
    meeting_sync_attempts,
    name,
    session_kind_id,
    ends_at,
    meeting_create_attempted_at,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at,
    starts_at
) values (
    :'sessionID',
    :'eventID',
    2,
    'Test Session',
    'virtual',
    '2026-06-01 10:30:00+00',
    current_timestamp - interval '5 minutes',
    false,
    'session-host@example.com',
    'zoom',
    true,
    current_timestamp,
    '2026-06-01 10:00:00+00'
);

-- Claimed session meeting marked keep (null) while claimed
insert into session (
    session_id,
    event_id,
    meeting_sync_attempts,
    name,
    session_kind_id,
    ends_at,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_provider_id,
    meeting_requested,
    meeting_sync_claimed_at,
    starts_at
) values (
    :'keptSessionID',
    :'eventID',
    4,
    'Kept Session',
    'virtual',
    '2026-06-01 10:30:00+00',
    null,
    'kept-session-host@example.com',
    'zoom',
    null,
    current_timestamp,
    '2026-06-01 10:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject non-positive retry delays
select throws_ok(
    format(
        $$select release_meeting_sync_claim(%L::uuid, null, null, current_timestamp, 0)$$,
        :'eventID'
    ),
    'P0001',
    'retry delay must be positive',
    'Should reject non-positive retry delays'
);

-- Should release a meeting sync claim with backoff and preserve sticky host and create tracking
select lives_ok(
    format(
        $$select release_meeting_sync_claim(%L::uuid, null, null, current_timestamp - interval '1 hour', 120)$$,
        :'eventID'
    ),
    'Should accept a stale event claim timestamp without error'
);
select isnt(
    (select meeting_sync_claimed_at from event where event_id = :'eventID'),
    null,
    'Should not clear event sync claim for stale claim timestamp'
);
select lives_ok(
    format(
        $$select release_meeting_sync_claim(%L::uuid, null, null, (select meeting_sync_claimed_at from event where event_id = %L::uuid), 120)$$,
        :'eventID',
        :'eventID'
    ),
    'Should release event meeting sync claim'
);
select is(
    (select meeting_provider_host_user from event where event_id = :'eventID'),
    null,
    'Should clear reserved host'
);
select is(
    (select meeting_sync_claimed_at from event where event_id = :'eventID'),
    null,
    'Should clear event sync claim timestamp'
);
select results_eq(
    format(
        $$
            select
                meeting_create_attempted_at,
                meeting_last_provider_host_user,
                meeting_next_sync_at,
                meeting_sync_attempts
            from event
            where event_id = %L::uuid
        $$,
        :'eventID'
    ),
    $$
        values (
            current_timestamp - interval '5 minutes',
            'host@example.com',
            current_timestamp + interval '120 seconds',
            2
        )
    $$,
    'Should preserve event create tracking, sticky host and attempts while scheduling backoff'
);

-- Should release a session meeting sync claim with backoff and preserve sticky host and create tracking
select lives_ok(
    format(
        $$select release_meeting_sync_claim(null, null, %L::uuid, current_timestamp - interval '1 hour', 240)$$,
        :'sessionID'
    ),
    'Should accept a stale session claim timestamp without error'
);
select isnt(
    (select meeting_sync_claimed_at from session where session_id = :'sessionID'),
    null,
    'Should not clear session sync claim for stale claim timestamp'
);
select lives_ok(
    format(
        $$select release_meeting_sync_claim(null, null, %L::uuid, (select meeting_sync_claimed_at from session where session_id = %L::uuid), 240)$$,
        :'sessionID',
        :'sessionID'
    ),
    'Should release session meeting sync claim'
);
select is(
    (select meeting_provider_host_user from session where session_id = :'sessionID'),
    null,
    'Should clear session reserved host'
);
select is(
    (select meeting_sync_claimed_at from session where session_id = :'sessionID'),
    null,
    'Should clear session sync claim timestamp'
);
select results_eq(
    format(
        $$
            select
                meeting_create_attempted_at,
                meeting_last_provider_host_user,
                meeting_next_sync_at,
                meeting_sync_attempts
            from session
            where session_id = %L::uuid
        $$,
        :'sessionID'
    ),
    $$
        values (
            current_timestamp - interval '5 minutes',
            'session-host@example.com',
            current_timestamp + interval '240 seconds',
            2
        )
    $$,
    'Should preserve session create tracking, sticky host and attempts while scheduling backoff'
);

-- Should release a claim without a delay using the 4-argument form and preserve prior sticky host
select lives_ok(
    format(
        $$select release_meeting_sync_claim(%L::uuid, null, null, (select meeting_sync_claimed_at from event where event_id = %L::uuid))$$,
        :'eventNoDelayID',
        :'eventNoDelayID'
    ),
    'Should release event claim without a retry delay'
);
select results_eq(
    format(
        $$
            select
                meeting_create_attempted_at,
                meeting_last_provider_host_user,
                meeting_next_sync_at,
                meeting_sync_attempts,
                meeting_sync_claimed_at
            from event
            where event_id = %L::uuid
        $$,
        :'eventNoDelayID'
    ),
    $$
        values (
            current_timestamp - interval '5 minutes',
            'prior-host@example.com',
            null::timestamptz,
            3,
            null::timestamptz
        )
    $$,
    'Should preserve prior sticky host and leave next_sync_at null when released without delay'
);

-- Should reset backoff and attempts when the claimed event state hash changed during the claim
select lives_ok(
    format(
        $$select release_meeting_sync_claim(%L::uuid, null, null, (select meeting_sync_claimed_at from event where event_id = %L::uuid), 1800, 'stale-claimed-hash')$$,
        :'eventEditedDuringClaimID',
        :'eventEditedDuringClaimID'
    ),
    'Should release event claim with mismatched sync state hash'
);
select results_eq(
    format(
        $$
            select
                meeting_create_attempted_at,
                meeting_last_provider_host_user,
                meeting_next_sync_at,
                meeting_sync_attempts,
                meeting_sync_claimed_at
            from event
            where event_id = %L::uuid
        $$,
        :'eventEditedDuringClaimID'
    ),
    $$
        values (
            current_timestamp - interval '5 minutes',
            'edited-claim-host@example.com',
            null::timestamptz,
            0,
            null::timestamptz
        )
    $$,
    'Should reset backoff and attempts while preserving create tracking and sticky host when state changed during claim'
);

-- Should release a claim on an event marked keep and leave it kept without backoff or stale attempts
select release_meeting_sync_claim(
    :'keptEventID',
    null,
    null,
    (select meeting_sync_claimed_at from event where event_id = :'keptEventID'),
    120
);
select is(
    (
        select jsonb_build_object(
            'meeting_in_sync', meeting_in_sync,
            'meeting_next_sync_at', meeting_next_sync_at,
            'meeting_provider_host_user', meeting_provider_host_user,
            'meeting_sync_attempts', meeting_sync_attempts,
            'meeting_sync_claimed_at', meeting_sync_claimed_at
        )
        from event
        where event_id = :'keptEventID'
    ),
    '{"meeting_in_sync": null, "meeting_next_sync_at": null, "meeting_provider_host_user": null, "meeting_sync_attempts": 0, "meeting_sync_claimed_at": null}'::jsonb,
    'Should release a kept event claim, reset attempts and keep it marked null without backoff'
);

-- Should release a claim on a session marked keep and leave it kept without backoff or stale attempts
select release_meeting_sync_claim(
    null,
    null,
    :'keptSessionID',
    (select meeting_sync_claimed_at from session where session_id = :'keptSessionID'),
    120
);
select is(
    (
        select jsonb_build_object(
            'meeting_in_sync', meeting_in_sync,
            'meeting_next_sync_at', meeting_next_sync_at,
            'meeting_provider_host_user', meeting_provider_host_user,
            'meeting_sync_attempts', meeting_sync_attempts,
            'meeting_sync_claimed_at', meeting_sync_claimed_at
        )
        from session
        where session_id = :'keptSessionID'
    ),
    '{"meeting_in_sync": null, "meeting_next_sync_at": null, "meeting_provider_host_user": null, "meeting_sync_attempts": 0, "meeting_sync_claimed_at": null}'::jsonb,
    'Should release a kept session claim, reset attempts and keep it marked null without backoff'
);

-- Should release an orphan meeting sync claim with backoff
select lives_ok(
    format(
        $$select release_meeting_sync_claim(null, %L::uuid, null, current_timestamp - interval '1 hour', 60)$$,
        :'meetingID'
    ),
    'Should accept a stale orphan meeting claim timestamp without error'
);
select isnt(
    (select sync_claimed_at from meeting where meeting_id = :'meetingID'),
    null,
    'Should not clear orphan meeting sync claim for stale claim timestamp'
);
select lives_ok(
    format(
        $$select release_meeting_sync_claim(null, %L::uuid, null, (select sync_claimed_at from meeting where meeting_id = %L::uuid), 60)$$,
        :'meetingID',
        :'meetingID'
    ),
    'Should release orphan meeting sync claim'
);
select is(
    (select sync_claimed_at from meeting where meeting_id = :'meetingID'),
    null,
    'Should clear orphan meeting sync claim timestamp'
);
select is(
    (select next_sync_at from meeting where meeting_id = :'meetingID'),
    current_timestamp + interval '60 seconds',
    'Should schedule orphan meeting backoff timestamp'
);
select isnt(
    (select updated_at from meeting where meeting_id = :'meetingID'),
    null,
    'Should update orphan meeting timestamp'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
