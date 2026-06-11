-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a360000-0000-0000-0000-000000000001'
\set eventCategoryID '3a360000-0000-0000-0000-000000000002'
\set eventID '3a360000-0000-0000-0000-000000000003'
\set eventNoMeetingID '3a360000-0000-0000-0000-000000000004'
\set groupCategoryID '3a360000-0000-0000-0000-000000000005'
\set groupID '3a360000-0000-0000-0000-000000000006'
\set missingGroupID '3a360000-0000-0000-0000-000000000007'
\set sessionMeetingID '3a360000-0000-0000-0000-000000000008'
\set sessionNoMeetingID '3a360000-0000-0000-0000-000000000009'
\set userID '3a360000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Test Group',
    'test-group',
    'A test group'
);

-- User (as previously published_by)
insert into "user" (user_id, auth_hash, email, username)
values (:'userID', 'user-hash', 'user@test.local', 'user');

-- Event (published, with meeting_in_sync=true to verify it gets set to false)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,

    capacity,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    published,
    published_at,
    published_by
) values (
    :'eventID',
    :'groupID',
    'Test Event',
    'test-event',
    'A test event',
    'UTC',
    :'eventCategoryID',
    'virtual',
    '2025-06-01 10:00:00+00',
    '2025-06-01 11:00:00+00',

    100,
    true,
    'zoom',
    true,
    true,
    now(),
    :'userID'
);

-- Event without meeting_requested (to verify meeting_in_sync is not changed)
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    meeting_in_sync,
    meeting_requested,
    published,
    published_at,
    published_by
) values (
    :'eventNoMeetingID',
    :'groupID',
    'Test Event No Meeting',
    'test-event-no-meeting',
    'A test event without meeting',
    'UTC',
    :'eventCategoryID',
    'in-person',
    '2025-06-02 10:00:00+00',
    '2025-06-02 11:00:00+00',
    null,
    false,
    true,
    now(),
    :'userID'
);

-- Session with meeting_requested=true (should be marked as out of sync)
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionMeetingID',
    :'eventID',
    'Session With Meeting',
    '2025-06-01 10:00:00+00',
    '2025-06-01 10:30:00+00',
    'virtual',
    true,
    'zoom',
    true
);

-- Session with meeting_requested=false (should NOT be marked as out of sync)
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_in_sync,
    meeting_requested
) values (
    :'sessionNoMeetingID',
    :'eventID',
    'Session Without Meeting',
    '2025-06-01 10:30:00+00',
    '2025-06-01 11:00:00+00',
    'in-person',
    null,
    false
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should clear published flags and metadata
select lives_ok(
    format(
        'select unpublish_event(null::uuid, %L::uuid, %L::uuid)',
        :'groupID',
        :'eventID'
    ),
    'Should clear published flags and metadata'
);

-- Should set published=false
select is(
    (select published from event where event_id = :'eventID'),
    false,
    'Should set published=false'
);

-- Should set published_at to null
select is(
    (select published_at from event where event_id = :'eventID'),
    null,
    'Should set published_at to null'
);

-- Should set published_by to null
select is(
    (select published_by from event where event_id = :'eventID'),
    null,
    'Should set published_by to null'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            event_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'event_unpublished',
            null::uuid,
            null::text,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'event',
            %L::uuid
        )
        $$,
        :'communityID',
        :'groupID',
        :'eventID',
        :'eventID'
    ),
    'Should create the expected audit row'
);

-- Should set event meeting_in_sync to false
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    false,
    'Should set event meeting_in_sync=false'
);

-- Should set session meeting_in_sync to false when meeting_requested=true
select is(
    (select meeting_in_sync from session where session_id = :'sessionMeetingID'),
    false,
    'Should set session meeting_in_sync=false when meeting_requested=true'
);

-- Should not change session meeting_in_sync when meeting_requested=false
select is(
    (select meeting_in_sync from session where session_id = :'sessionNoMeetingID'),
    null,
    'Should not change session meeting_in_sync when meeting_requested=false'
);

-- Should unpublish event when meeting_requested=false
select lives_ok(
    format(
        'select unpublish_event(null::uuid, %L::uuid, %L::uuid)',
        :'groupID',
        :'eventNoMeetingID'
    ),
    'Should unpublish event when meeting_requested=false'
);

-- Should keep event meeting_in_sync unchanged when meeting_requested=false
select is(
    (select meeting_in_sync from event where event_id = :'eventNoMeetingID'),
    null,
    'Should keep event meeting_in_sync unchanged when meeting_requested=false'
);

-- Should throw error when group_id does not match
select throws_ok(
    format(
        'select unpublish_event(null::uuid, %L::uuid, %L::uuid)',
        :'missingGroupID',
        :'eventID'
    ),
    'event not found or inactive',
    'Should throw error when group_id does not match'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
