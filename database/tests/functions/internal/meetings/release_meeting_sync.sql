-- Tests completing event and session meeting sync claims.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(22);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f2090000-0000-0000-0000-000000000001'
\set errorEventID 'f2090000-0000-0000-0000-000000000002'
\set eventCategoryID 'f2090000-0000-0000-0000-000000000003'
\set eventID 'f2090000-0000-0000-0000-000000000004'
\set groupCategoryID 'f2090000-0000-0000-0000-000000000005'
\set groupID 'f2090000-0000-0000-0000-000000000006'
\set keepEventID 'f2090000-0000-0000-0000-000000000010'
\set keepMatchEventID 'f2090000-0000-0000-0000-000000000011'
\set keepSessionID 'f2090000-0000-0000-0000-000000000012'
\set notHeldEventID 'f2090000-0000-0000-0000-000000000009'
\set nullHashEventID 'f2090000-0000-0000-0000-000000000013'
\set sessionID 'f2090000-0000-0000-0000-000000000007'
\set staleEventID 'f2090000-0000-0000-0000-000000000008'
\set staleSessionID 'f2090000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Claimed virtual event whose sync succeeds
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'meeting_error', 'previous error',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'release-sync-host@example.com',
    'meeting_sync_claimed_at', '2024-01-01 00:00:00+00',
    'timezone', 'America/New_York'
));

-- Claimed virtual event whose sync fails
select fx_event(:'errorEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'release-sync-error-host@example.com',
    'meeting_sync_claimed_at', '2024-01-01 00:00:00+00',
    'timezone', 'America/New_York'
));

-- Claimed event marked keep by an update during the claim, with an earlier error
select fx_event(:'keepEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'meeting_error', 'previous keep error',
    'meeting_in_sync', null,
    'meeting_provider_host_user', 'release-sync-keep-host@example.com',
    'meeting_requested', null,
    'meeting_sync_claimed_at', '2024-01-03 00:00:00+00',
    'timezone', 'America/New_York'
));

-- Claimed event marked keep during the claim without other state changes
select fx_event(:'keepMatchEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'meeting_error', 'previous keep match error',
    'meeting_in_sync', null,
    'meeting_provider_host_user', 'release-sync-keep-match-host@example.com',
    'meeting_requested', null,
    'meeting_sync_claimed_at', '2024-01-03 00:00:00+00',
    'timezone', 'America/New_York'
));

-- Event claimed by another worker after the caller's claim expired
select fx_event(:'notHeldEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'meeting_error', 'previous not held error',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'release-sync-not-held-host@example.com',
    'meeting_sync_claimed_at', '2024-01-02 00:00:00+00',
    'timezone', 'America/New_York'
));

-- Event whose state changed after the worker read it, with an earlier error
select fx_event(:'staleEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'meeting_error', 'previous stale error',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'release-sync-stale-host@example.com',
    'meeting_sync_claimed_at', '2024-01-02 00:00:00+00',
    'timezone', 'America/New_York'
));

-- Claimed event released with a missing synchronized state hash
select fx_event(:'nullHashEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'meeting_error', 'previous null hash error',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'release-sync-null-hash-host@example.com',
    'meeting_sync_claimed_at', '2024-01-04 00:00:00+00',
    'timezone', 'America/New_York'
));

-- Claimed session whose sync succeeds, with an earlier error
insert into session (
    event_id,
    meeting_error,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_sync_claimed_at,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    :'eventID',
    'previous session error',
    false,
    'release-sync-session-host@example.com',
    '2024-01-01 00:00:00+00',
    'Release Sync Session',
    :'sessionID',
    'virtual',
    '2025-06-01 10:00:00-04'
);

-- Claimed session marked keep by an update during the claim, with an earlier error
insert into session (
    event_id,
    meeting_error,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_requested,
    meeting_sync_claimed_at,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    :'eventID',
    'previous keep session error',
    null,
    'release-sync-keep-session-host@example.com',
    null,
    '2024-01-03 00:00:00+00',
    'Release Sync Keep Session',
    :'keepSessionID',
    'virtual',
    '2025-06-01 11:00:00-04'
);

-- Session whose state changed after the worker read it, with an earlier error
insert into session (
    event_id,
    meeting_error,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_sync_claimed_at,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    :'eventID',
    'previous stale session error',
    false,
    'release-sync-stale-session-host@example.com',
    '2024-01-02 00:00:00+00',
    'Release Sync Stale Session',
    :'staleSessionID',
    'virtual',
    '2025-06-01 12:00:00-04'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should release a held event claim and clear the error on success
select is(
    release_meeting_sync(
        :'eventID',
        null,
        '2024-01-01 00:00:00+00',
        get_event_meeting_sync_state_hash(:'eventID'),
        null
    ),
    true,
    'Should report the event claim as held'
);
select results_eq(
    format(
        $$ select meeting_error, meeting_in_sync, meeting_provider_host_user, meeting_sync_claimed_at from event where event_id = %L $$,
        :'eventID'
    ),
    $$ values (null::text, true, null::text, null::timestamptz) $$,
    'Should mark the event in sync and clear the claim and error'
);

-- Should record the error while releasing a held claim
select is(
    release_meeting_sync(
        :'errorEventID',
        null,
        '2024-01-01 00:00:00+00',
        get_event_meeting_sync_state_hash(:'errorEventID'),
        'provider rejected the meeting'
    ),
    true,
    'Should report the failing event claim as held'
);
select results_eq(
    format(
        $$ select meeting_error, meeting_in_sync, meeting_sync_claimed_at from event where event_id = %L $$,
        :'errorEventID'
    ),
    $$ values ('provider rejected the meeting', true, null::timestamptz) $$,
    'Should store the error and keep the row in sync with the synchronized state'
);

-- Should keep an event marked keep during the claim when its state changed
select is(
    release_meeting_sync(
        :'keepEventID',
        null,
        '2024-01-03 00:00:00+00',
        'claimed-state-hash',
        'late keep error'
    ),
    true,
    'Should report the kept event claim as held'
);
select results_eq(
    format(
        $$ select meeting_error, meeting_in_sync, meeting_provider_host_user, meeting_sync_claimed_at from event where event_id = %L $$,
        :'keepEventID'
    ),
    $$ values ('previous keep error', null::boolean, null::text, null::timestamptz) $$,
    'Should keep the changed event marked keep and its previous error while clearing the claim'
);

-- Should keep an event marked keep during the claim when its state is unchanged
select is(
    release_meeting_sync(
        :'keepMatchEventID',
        null,
        '2024-01-03 00:00:00+00',
        get_event_meeting_sync_state_hash(:'keepMatchEventID'),
        'provider rejected the kept meeting'
    ),
    true,
    'Should report the unchanged kept event claim as held'
);
select results_eq(
    format(
        $$ select meeting_error, meeting_in_sync, meeting_provider_host_user, meeting_sync_claimed_at from event where event_id = %L $$,
        :'keepMatchEventID'
    ),
    $$ values ('provider rejected the kept meeting', null::boolean, null::text, null::timestamptz) $$,
    'Should store the error and keep the unchanged event marked keep while clearing the claim'
);

-- Should keep a session marked keep during the claim when its state changed
select is(
    release_meeting_sync(
        null,
        :'keepSessionID',
        '2024-01-03 00:00:00+00',
        'claimed-state-hash',
        'late keep session error'
    ),
    true,
    'Should report the kept session claim as held'
);
select results_eq(
    format(
        $$ select meeting_error, meeting_in_sync, meeting_provider_host_user, meeting_sync_claimed_at from session where session_id = %L $$,
        :'keepSessionID'
    ),
    $$ values ('previous keep session error', null::boolean, null::text, null::timestamptz) $$,
    'Should keep the changed session marked keep and its previous error while clearing the claim'
);

-- Should not claim rows marked keep during a claim for deletion after release
select is(
    claim_meeting_out_of_sync(),
    null::jsonb,
    'Should not claim kept events and sessions for deletion after release'
);

-- Should leave a session out of sync and keep its error when the state changed since the worker read it
select is(
    release_meeting_sync(
        null,
        :'staleSessionID',
        '2024-01-02 00:00:00+00',
        'stale-session-state-hash',
        'late session error'
    ),
    true,
    'Should still release a held session claim whose state changed'
);
select results_eq(
    format(
        $$ select meeting_error, meeting_in_sync, meeting_provider_host_user, meeting_sync_claimed_at from session where session_id = %L $$,
        :'staleSessionID'
    ),
    $$ values ('previous stale session error', false, null::text, null::timestamptz) $$,
    'Should keep the session out of sync and the previous error without recording the late error'
);

-- Should leave the row out of sync and keep its error when the state changed since the worker read it
select is(
    release_meeting_sync(
        :'staleEventID',
        null,
        '2024-01-02 00:00:00+00',
        'stale-state-hash',
        'late error'
    ),
    true,
    'Should still release a held claim whose state changed'
);
select results_eq(
    format(
        $$ select meeting_error, meeting_in_sync, meeting_provider_host_user, meeting_sync_claimed_at from event where event_id = %L $$,
        :'staleEventID'
    ),
    $$ values ('previous stale error', false, null::text, null::timestamptz) $$,
    'Should keep the row out of sync and the previous error without recording the late error'
);

-- Should leave the row out of sync and keep its error without a synchronized state hash
select is(
    release_meeting_sync(
        :'nullHashEventID',
        null,
        '2024-01-04 00:00:00+00',
        null,
        'null hash error'
    ),
    true,
    'Should release a held claim without a synchronized state hash'
);
select results_eq(
    format(
        $$ select meeting_error, meeting_in_sync, meeting_provider_host_user, meeting_sync_claimed_at from event where event_id = %L $$,
        :'nullHashEventID'
    ),
    $$ values ('previous null hash error', false, null::text, null::timestamptz) $$,
    'Should keep the row out of sync and the previous error without a synchronized state hash'
);

-- Should ignore a claim that is no longer held
select is(
    release_meeting_sync(
        :'notHeldEventID',
        null,
        '2024-01-01 00:00:00+00',
        get_event_meeting_sync_state_hash(:'notHeldEventID'),
        null
    ),
    false,
    'Should report a claim that is no longer held'
);
select results_eq(
    format(
        $$ select meeting_error, meeting_in_sync, meeting_provider_host_user, meeting_sync_claimed_at from event where event_id = %L $$,
        :'notHeldEventID'
    ),
    $$ values ('previous not held error', false, 'release-sync-not-held-host@example.com', '2024-01-02 00:00:00+00'::timestamptz) $$,
    'Should leave a row whose claim is no longer held unchanged'
);

-- Should release a held session claim
select is(
    release_meeting_sync(
        null,
        :'sessionID',
        '2024-01-01 00:00:00+00',
        get_session_meeting_sync_state_hash(:'sessionID'),
        null
    ),
    true,
    'Should report the session claim as held'
);
select results_eq(
    format(
        $$ select meeting_error, meeting_in_sync, meeting_provider_host_user, meeting_sync_claimed_at from session where session_id = %L $$,
        :'sessionID'
    ),
    $$ values (null::text, true, null::text, null::timestamptz) $$,
    'Should mark the session in sync and clear the claim and error'
);

-- Should do nothing without an event or session
select is(
    release_meeting_sync(null, null, '2024-01-01 00:00:00+00', 'hash', null),
    false,
    'Should do nothing without an event or session'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
