-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '3a0a0000-0000-0000-0000-000000000001'
\set eventCategoryID '3a0a0000-0000-0000-0000-000000000002'
\set eventID '3a0a0000-0000-0000-0000-000000000003'
\set eventNoMeetingID '3a0a0000-0000-0000-0000-000000000004'
\set groupCategoryID '3a0a0000-0000-0000-0000-000000000005'
\set groupID '3a0a0000-0000-0000-0000-000000000006'
\set missingGroupID '3a0a0000-0000-0000-0000-000000000007'
\set sessionMeetingID '3a0a0000-0000-0000-0000-000000000008'
\set sessionNoMeetingID '3a0a0000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'allianceID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant alliance for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Event Category
insert into event_category (event_category_id, name, alliance_id)
values (:'eventCategoryID', 'Conference', :'allianceID');

-- Group Category
insert into group_category (group_category_id, name, alliance_id)
values (:'groupCategoryID', 'Technology', :'allianceID');

-- Group
insert into "group" (
    group_id,
    alliance_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'groupID',
    :'allianceID',
    'Kubernetes Study Group',
    'kubernetes-study-group',
    'A study group focused on Kubernetes best practices and implementation',
    :'groupCategoryID'
);

-- Event
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
    published
) values (
    :'eventID',
    :'groupID',
    'Container Security Workshop',
    'container-security-workshop',
    'Deep dive into container security best practices and threat mitigation',
    'America/New_York',
    :'eventCategoryID',
    'virtual',
    now(),
    now() + interval '1 hour',

    100,
    true,
    'zoom',
    true,
    true
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
    published
) values (
    :'eventNoMeetingID',
    :'groupID',
    'Event No Meeting',
    'event-no-meeting',
    'An event without meeting requested',
    'America/New_York',
    :'eventCategoryID',
    'in-person',
    now(),
    now() + interval '1 hour',
    null,
    false,
    true
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
    now(),
    now() + interval '30 minutes',
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
    now() + interval '30 minutes',
    now() + interval '1 hour',
    'in-person',
    null,
    false
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should set deleted=true
select lives_ok(
    format(
        'select delete_event(null::uuid, %L::uuid, %L::uuid)',
        :'groupID',
        :'eventID'
    ),
    'Should execute delete_event successfully'
);
select is(
    (select deleted from event where event_id = :'eventID'),
    true,
    'Should mark event as deleted'
);

-- Should set deleted_at timestamp
select isnt(
    (select deleted_at from event where event_id = :'eventID'),
    null,
    'Should set deleted_at timestamp'
);

-- Should set published=false
select is(
    (select published from event where event_id = :'eventID'),
    false,
    'Should set published=false'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            alliance_id,
            group_id,
            event_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'event_deleted',
            null::uuid,
            null::text,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'event',
            %L::uuid
        )
        $$,
        :'allianceID', :'groupID', :'eventID', :'eventID'
    ),
    'Should create the expected audit row'
);

-- Should set meeting_in_sync=false
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    false,
    'Should mark meeting_in_sync false when meeting was requested'
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

-- Should not change event meeting_in_sync when meeting_requested=false
select lives_ok(
    format(
        'select delete_event(null::uuid, %L::uuid, %L::uuid)',
        :'groupID',
        :'eventNoMeetingID'
    ),
    'Should delete event when meeting_requested=false'
);
select is(
    (select meeting_in_sync from event where event_id = :'eventNoMeetingID'),
    null,
    'Should keep event meeting_in_sync unchanged when meeting_requested=false'
);

-- Should keep event in database (soft delete)
select is(
    (select count(*)::int from event where event_id = :'eventID'),
    1,
    'Should keep event in database (soft delete)'
);

-- Should throw error when group_id does not match
select throws_ok(
    format(
        $$select delete_event(null::uuid, %L::uuid, %L::uuid)$$,
        :'missingGroupID', :'eventID'
    ),
    'event not found or inactive',
    'Should throw error when group_id does not match'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
