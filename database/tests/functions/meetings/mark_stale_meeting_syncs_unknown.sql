-- Tests marking stale meeting sync claims as unknown.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '7a0a0000-0000-0000-0000-000000000001'
\set eventCategoryID '7a0a0000-0000-0000-0000-000000000002'
\set eventFreshID '7a0a0000-0000-0000-0000-000000000008'
\set eventID '7a0a0000-0000-0000-0000-000000000003'
\set eventLinkedID '7a0a0000-0000-0000-0000-000000000009'
\set groupCategoryID '7a0a0000-0000-0000-0000-000000000004'
\set groupID '7a0a0000-0000-0000-0000-000000000005'
\set meetingEventLinkedID '7a0a0000-0000-0000-0000-000000000010'
\set meetingFreshID '7a0a0000-0000-0000-0000-000000000011'
\set meetingID '7a0a0000-0000-0000-0000-000000000006'
\set meetingSessionLinkedID '7a0a0000-0000-0000-0000-000000000012'
\set sessionFreshID '7a0a0000-0000-0000-0000-000000000013'
\set sessionID '7a0a0000-0000-0000-0000-000000000007'
\set sessionLinkedID '7a0a0000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Stale claimed event meeting
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2026-06-01 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'host@example.com',
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'meeting_sync_claimed_at', current_timestamp - interval '30 minutes',
    'published', true,
    'starts_at', '2026-06-01 10:00:00+00'
));

-- Event meeting claimed within the processing timeout
select fx_event(:'eventFreshID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2026-06-04 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_host_user', 'fresh-host@example.com',
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'meeting_sync_claimed_at', current_timestamp - interval '1 minute',
    'published', true,
    'starts_at', '2026-06-04 10:00:00+00'
));

-- Unclaimed event owning the stale claimed linked meetings
select fx_event(:'eventLinkedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2026-06-05 11:00:00+00',
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', '2026-06-05 10:00:00+00'
));

-- Stale claimed session meeting
insert into session (
    session_id,
    event_id,
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
    :'sessionID',
    :'eventID',
    'Test Session',
    'virtual',
    '2026-06-01 10:30:00+00',
    false,
    'session-host@example.com',
    'zoom',
    true,
    current_timestamp - interval '30 minutes',
    '2026-06-01 10:00:00+00'
);

-- Session meeting claimed within the processing timeout
insert into session (
    session_id,
    event_id,
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
    :'sessionFreshID',
    :'eventFreshID',
    'Fresh Session',
    'virtual',
    '2026-06-04 10:30:00+00',
    false,
    'fresh-session-host@example.com',
    'zoom',
    true,
    current_timestamp - interval '1 minute',
    '2026-06-04 10:00:00+00'
);

-- Unclaimed session owning the stale claimed session-linked meeting
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    ends_at,
    starts_at
) values (
    :'sessionLinkedID',
    :'eventLinkedID',
    'Linked Session',
    'virtual',
    '2026-06-05 10:30:00+00',
    '2026-06-05 10:00:00+00'
);

-- Stale claimed orphan meeting
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,
    sync_claimed_at
) values (
    :'meetingID',
    'https://zoom.us/j/orphan-stale-syncs',
    'zoom',
    'orphan-stale-syncs',
    current_timestamp - interval '30 minutes'
);

-- Orphan meeting claimed within the processing timeout
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,
    sync_claimed_at
) values (
    :'meetingFreshID',
    'https://zoom.us/j/orphan-fresh-syncs',
    'zoom',
    'orphan-fresh-syncs',
    current_timestamp - interval '1 minute'
);

-- Stale claimed meeting still linked to an event
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,
    event_id,
    sync_claimed_at
) values (
    :'meetingEventLinkedID',
    'https://zoom.us/j/event-linked-stale-syncs',
    'zoom',
    'event-linked-stale-syncs',
    :'eventLinkedID',
    current_timestamp - interval '30 minutes'
);

-- Stale claimed meeting still linked to a session
insert into meeting (
    meeting_id,
    join_url,
    meeting_provider_id,
    provider_meeting_id,
    session_id,
    sync_claimed_at
) values (
    :'meetingSessionLinkedID',
    'https://zoom.us/j/session-linked-stale-syncs',
    'zoom',
    'session-linked-stale-syncs',
    :'sessionLinkedID',
    current_timestamp - interval '30 minutes'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject non-positive processing timeouts
select throws_ok(
    $$select mark_stale_meeting_syncs_unknown(0)$$,
    'P0001',
    'processing timeout must be positive',
    'Should reject non-positive processing timeouts'
);

-- Should mark stale event, session, and orphan meeting sync claims
select is(
    mark_stale_meeting_syncs_unknown(900),
    3,
    'Should mark stale event, session, and orphan meeting sync claims'
);

-- Should mark the stale event meeting unknown and release its claim
select results_eq(
    format(
        $query$
        select
            meeting_error,
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
        'meeting synchronization outcome unknown after processing timeout',
        true,
        null::text,
        null::timestamptz
    )
    $expected$,
    'Should mark the stale event meeting unknown and release its claim'
);

-- Should mark the stale session meeting unknown and release its claim
select results_eq(
    format(
        $query$
        select
            meeting_error,
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
        'meeting synchronization outcome unknown after processing timeout',
        true,
        null::text,
        null::timestamptz
    )
    $expected$,
    'Should mark the stale session meeting unknown and release its claim'
);

-- Should release the stale orphan meeting claim
select results_eq(
    format(
        $query$
        select
            sync_claimed_at,
            updated_at
        from meeting
        where meeting_id = %L::uuid
        $query$,
        :'meetingID'
    ),
    $expected$
    values (
        null::timestamptz,
        current_timestamp
    )
    $expected$,
    'Should release the stale orphan meeting claim'
);

-- Should keep the event meeting claimed within the processing timeout
select results_eq(
    format(
        $query$
        select
            meeting_error,
            meeting_in_sync,
            meeting_provider_host_user,
            meeting_sync_claimed_at
        from event
        where event_id = %L::uuid
        $query$,
        :'eventFreshID'
    ),
    $expected$
    values (
        null::text,
        false,
        'fresh-host@example.com',
        current_timestamp - interval '1 minute'
    )
    $expected$,
    'Should keep the event meeting claimed within the processing timeout'
);

-- Should keep the session meeting claimed within the processing timeout
select results_eq(
    format(
        $query$
        select
            meeting_error,
            meeting_in_sync,
            meeting_provider_host_user,
            meeting_sync_claimed_at
        from session
        where session_id = %L::uuid
        $query$,
        :'sessionFreshID'
    ),
    $expected$
    values (
        null::text,
        false,
        'fresh-session-host@example.com',
        current_timestamp - interval '1 minute'
    )
    $expected$,
    'Should keep the session meeting claimed within the processing timeout'
);

-- Should keep the orphan meeting claimed within the processing timeout
select results_eq(
    format(
        $query$
        select
            sync_claimed_at,
            updated_at
        from meeting
        where meeting_id = %L::uuid
        $query$,
        :'meetingFreshID'
    ),
    $expected$
    values (
        current_timestamp - interval '1 minute',
        null::timestamptz
    )
    $expected$,
    'Should keep the orphan meeting claimed within the processing timeout'
);

-- Should keep the stale claim on a meeting linked to an event
select results_eq(
    format(
        $query$
        select
            sync_claimed_at,
            updated_at
        from meeting
        where meeting_id = %L::uuid
        $query$,
        :'meetingEventLinkedID'
    ),
    $expected$
    values (
        current_timestamp - interval '30 minutes',
        null::timestamptz
    )
    $expected$,
    'Should keep the stale claim on a meeting linked to an event'
);

-- Should keep the stale claim on a meeting linked to a session
select results_eq(
    format(
        $query$
        select
            sync_claimed_at,
            updated_at
        from meeting
        where meeting_id = %L::uuid
        $query$,
        :'meetingSessionLinkedID'
    ),
    $expected$
    values (
        current_timestamp - interval '30 minutes',
        null::timestamptz
    )
    $expected$,
    'Should keep the stale claim on a meeting linked to a session'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
