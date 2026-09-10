-- Tests completing event and session meeting sync claims.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f2090000-0000-0000-0000-000000000001'
\set errorEventID 'f2090000-0000-0000-0000-000000000002'
\set eventCategoryID 'f2090000-0000-0000-0000-000000000003'
\set eventID 'f2090000-0000-0000-0000-000000000004'
\set groupCategoryID 'f2090000-0000-0000-0000-000000000005'
\set groupID 'f2090000-0000-0000-0000-000000000006'
\set sessionID 'f2090000-0000-0000-0000-000000000007'
\set staleEventID 'f2090000-0000-0000-0000-000000000008'

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

-- Event whose claim was re-taken after the worker started
select fx_event(:'staleEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'release-sync-stale-host@example.com',
    'meeting_sync_claimed_at', '2024-01-02 00:00:00+00',
    'timezone', 'America/New_York'
));

-- Claimed session
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
    'Release Sync Session',
    'virtual',
    false,
    'release-sync-session-host@example.com',
    '2024-01-01 00:00:00+00',
    '2025-06-01 10:00:00-04'
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

-- Should leave the row out of sync when the state changed since the worker read it
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
        $$ select meeting_error, meeting_in_sync, meeting_sync_claimed_at from event where event_id = %L $$,
        :'staleEventID'
    ),
    $$ values (null::text, false, null::timestamptz) $$,
    'Should keep the row out of sync without recording the late error'
);

-- Should ignore a claim that is no longer held
select is(
    release_meeting_sync(
        :'staleEventID',
        null,
        '2024-01-01 00:00:00+00',
        get_event_meeting_sync_state_hash(:'staleEventID'),
        null
    ),
    false,
    'Should report a claim that is no longer held'
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
    'Should mark the session in sync and clear the claim'
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
