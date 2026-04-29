-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000211'
\set communityID '00000000-0000-0000-0000-000000000201'
\set eventID '00000000-0000-0000-0000-000000000212'
\set eventStaleClaimID '00000000-0000-0000-0000-000000000215'
\set groupCategoryID '00000000-0000-0000-0000-000000000210'
\set groupID '00000000-0000-0000-0000-000000000202'
\set orphanMeetingID '00000000-0000-0000-0000-000000000214'
\set sessionID '00000000-0000-0000-0000-000000000213'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'A test community', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'categoryID', 'Conference', :'communityID');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, description)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group', 'A test group');

-- Event
insert into event (
    description,
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_sync_claimed_at,
    name,
    slug,
    timezone
) values (
    'A test event',
    :'eventID',
    :'categoryID',
    'virtual',
    :'groupID',
    false,
    'event-claim-host@example.com',
    current_timestamp,
    'Test Event',
    'test-event',
    'America/New_York'
);

-- Event with stale claim
insert into event (
    description,
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    meeting_error,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_sync_claimed_at,
    name,
    slug,
    timezone
) values (
    'A stale claim event',
    :'eventStaleClaimID',
    :'categoryID',
    'virtual',
    :'groupID',
    'Previous sync error',
    false,
    'event-stale-claim-host@example.com',
    current_timestamp,
    'Stale Claim Event',
    'stale-claim-event',
    'America/New_York'
);

-- Session
insert into session (
    event_id,
    meeting_in_sync,
    meeting_provider_host_user,
    meeting_sync_claimed_at,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    :'eventID',
    false,
    'session-claim-host@example.com',
    current_timestamp,
    'Test Session',
    :'sessionID',
    'virtual',
    '2025-06-01 10:00:00-04'
);

-- Orphan meeting
insert into meeting (meeting_id, meeting_provider_id, provider_meeting_id, join_url)
values (:'orphanMeetingID', 'zoom', 'provider-001', 'https://zoom.us/j/provider-001');

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

-- Should delete orphan meeting when no event/session exists
select lives_ok(
    format(
        $$select set_meeting_error(%L::text, null, %L::uuid, null, null, null)$$,
        'orphan sync failed',
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
