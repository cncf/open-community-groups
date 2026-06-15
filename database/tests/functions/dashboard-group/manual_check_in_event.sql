-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '3a2a0000-0000-0000-0000-000000000001'
\set attendeeUserID '3a2a0000-0000-0000-0000-000000000002'
\set communityID '3a2a0000-0000-0000-0000-000000000003'
\set eventCategoryID '3a2a0000-0000-0000-0000-000000000004'
\set eventID '3a2a0000-0000-0000-0000-000000000005'
\set groupCategoryID '3a2a0000-0000-0000-0000-000000000006'
\set groupID '3a2a0000-0000-0000-0000-000000000007'
\set missingUserID '3a2a0000-0000-0000-0000-000000000008'

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
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'actorUserID', 'hash-1', 'actor@example.com', true, 'actor'),
    (:'attendeeUserID', 'hash-2', 'attendee@example.com', true, 'attendee'),
    (:'missingUserID', 'hash-3', 'missing@example.com', true, 'missing');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group');

-- Event
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    starts_at,
    published,
    published_at
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Manual Check-In Event',
    'manual-check-in-event',
    'An event for manual check-in tests',
    'UTC',
    now() + interval '3 hours',
    true,
    now()
);

-- Registered attendee
insert into event_attendee (event_id, user_id)
values (:'eventID', :'attendeeUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should manually check in a registered attendee
select lives_ok(
    format(
        'select manual_check_in_event(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'actorUserID',
        :'communityID',
        :'eventID',
        :'attendeeUserID'
    ),
    'Should manually check in a registered attendee'
);

-- Should mark the attendee as checked in
select is(
    (
        select checked_in
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'attendeeUserID'::uuid
    ),
    true,
    'Should mark the attendee as checked in'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            event_id,
            group_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'event_attendee_checked_in',
            %L::uuid,
            'actor',
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'user',
            %L::uuid
        )
        $$,
        :'actorUserID',
        :'communityID',
        :'eventID',
        :'groupID',
        :'attendeeUserID'
    ),
    'Should create the expected audit row'
);

-- Should reject manual check-in for users that are not registered
select throws_ok(
    format(
        'select manual_check_in_event(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
        :'actorUserID',
        :'communityID',
        :'eventID',
        :'missingUserID'
    ),
    'user is not registered for this event',
    'Should reject manual check-in for users that are not registered'
);

-- Should not create an audit row when manual check-in fails
select is(
    (select count(*)::int from audit_log),
    1,
    'Should not create an audit row when manual check-in fails'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
