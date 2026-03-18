-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCanceled '00000000-0000-0000-0000-000000000050'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventDeleted '00000000-0000-0000-0000-000000000044'
\set eventDisabledWaitlist '00000000-0000-0000-0000-000000000052'
\set eventFull '00000000-0000-0000-0000-000000000048'
\set eventInactiveGroup '00000000-0000-0000-0000-000000000045'
\set eventOK '00000000-0000-0000-0000-000000000041'
\set eventPast '00000000-0000-0000-0000-000000000047'
\set eventUnlimited '00000000-0000-0000-0000-000000000049'
\set eventUnpublished '00000000-0000-0000-0000-000000000046'
\set eventWaitlist '00000000-0000-0000-0000-000000000051'
\set groupID '00000000-0000-0000-0000-000000000021'
\set inactiveGroupID '00000000-0000-0000-0000-000000000022'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'
\set user3ID '00000000-0000-0000-0000-000000000033'
\set user4ID '00000000-0000-0000-0000-000000000034'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Users
insert into "user" (user_id, auth_hash, email, username)
values
    (:'user1ID', 'h', 'u1@test.com', 'u1'),
    (:'user2ID', 'h', 'u2@test.com', 'u2'),
    (:'user3ID', 'h', 'u3@test.com', 'u3'),
    (:'user4ID', 'h', 'u4@test.com', 'u4');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, active, deleted)
values
    (:'groupID', :'communityID', :'categoryID', 'Active Group', 'active-group', true, false),
    (:'inactiveGroupID', :'communityID', :'categoryID', 'Inactive Group', 'inactive-group', false, false);

insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    canceled,
    deleted,
    starts_at,
    ends_at,
    capacity,
    waitlist_enabled
)
values
    (:'eventOK', 'OK', 'ok', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null, null, false),
    (:'eventCanceled', 'Canceled', 'canceled', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, true, false, null, null, 1, true),
    (:'eventDeleted', 'Deleted', 'deleted', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, true, null, null, null, false),
    (:'eventInactiveGroup', 'Inactive Group', 'inactive-group', 'd', 'UTC', :'eventCategoryID', 'in-person', :'inactiveGroupID', true, false, false, null, null, null, false),
    (:'eventUnpublished', 'Unpublished', 'unpublished', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', false, false, false, null, null, null, false),
    (:'eventPast', 'Past', 'past', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, current_timestamp - interval '2 hours', current_timestamp - interval '1 hour', null, false),
    (:'eventDisabledWaitlist', 'Disabled Waitlist', 'disabled-waitlist', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null, 2, false),
    (:'eventFull', 'Full', 'full', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null, 1, true),
    (:'eventUnlimited', 'Unlimited', 'unlimited', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null, null, false),
    (:'eventWaitlist', 'Waitlist', 'waitlist', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, null, 1, true);

-- Event Attendees
insert into event_attendee (event_id, user_id) values
    (:'eventOK', :'user1ID'),
    (:'eventDisabledWaitlist', :'user1ID'),
    (:'eventDisabledWaitlist', :'user2ID'),
    (:'eventPast', :'user1ID'),
    (:'eventFull', :'user1ID'),
    (:'eventUnlimited', :'user1ID');

-- Event Waitlists
insert into event_waitlist (event_id, user_id, created_at) values
    (:'eventCanceled', :'user4ID', current_timestamp),
    (:'eventDisabledWaitlist', :'user3ID', current_timestamp),
    (:'eventFull', :'user2ID', current_timestamp),
    (:'eventFull', :'user3ID', current_timestamp + interval '1 minute'),
    (:'eventUnlimited', :'user2ID', current_timestamp),
    (:'eventUnlimited', :'user4ID', current_timestamp + interval '1 minute'),
    (:'eventWaitlist', :'user2ID', current_timestamp);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should remove an attendee from a normal event
select is(
    leave_event(:'communityID'::uuid, :'eventOK'::uuid, :'user1ID'::uuid)::jsonb,
    '{"left_status":"attendee","promoted_user_ids":[]}'::jsonb,
    'Removes attendee and returns attendee leave payload'
);

-- Should remove attendee record after leaving
select ok(
    not exists(
        select 1
        from event_attendee
        where event_id = :'eventOK'::uuid and user_id = :'user1ID'::uuid
    ),
    'Deletes attendee row after leaving'
);

-- Should allow a user to leave the waitlist
select is(
    leave_event(:'communityID'::uuid, :'eventWaitlist'::uuid, :'user2ID'::uuid)::jsonb,
    '{"left_status":"waitlisted","promoted_user_ids":[]}'::jsonb,
    'Removes waitlisted user and returns waitlisted leave payload'
);

-- Should remove waitlist row after leaving the waitlist
select ok(
    not exists(
        select 1
        from event_waitlist
        where event_id = :'eventWaitlist'::uuid and user_id = :'user2ID'::uuid
    ),
    'Deletes waitlist row after leaving the waitlist'
);

-- Should promote the next waitlisted user when a confirmed attendee leaves a full event
select is(
    leave_event(:'communityID'::uuid, :'eventFull'::uuid, :'user1ID'::uuid)::jsonb,
    format('{"left_status":"attendee","promoted_user_ids":["%s"]}', :'user2ID')::jsonb,
    'Promotes the oldest waitlisted user when capacity opens'
);

-- Should move the promoted user into attendees and remove them from the waitlist
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'eventFull'::uuid
            ),
            'waitlist', (
                select jsonb_agg(user_id order by user_id)
                from event_waitlist
                where event_id = :'eventFull'::uuid
            )
        )
    ),
    format('{"attendees":["%s"],"waitlist":["%s"]}', :'user2ID', :'user3ID')::jsonb,
    'Moves the promoted user into attendees and keeps the remaining waitlist order'
);

-- Should continue promoting existing waitlisted users after waitlist is disabled
select is(
    leave_event(:'communityID'::uuid, :'eventDisabledWaitlist'::uuid, :'user1ID'::uuid)::jsonb,
    format('{"left_status":"attendee","promoted_user_ids":["%s"]}', :'user3ID')::jsonb,
    'Promotes existing waitlisted users even after waitlist is disabled'
);

-- Should promote the full remaining queue when an unlimited event loses an attendee
select is(
    leave_event(:'communityID'::uuid, :'eventUnlimited'::uuid, :'user1ID'::uuid)::jsonb,
    format(
        '{"left_status":"attendee","promoted_user_ids":["%s","%s"]}',
        :'user2ID',
        :'user4ID'
    )::jsonb,
    'Promotes all waitlisted users when the event capacity is unlimited'
);

-- Should move all waitlisted users into attendees for unlimited-capacity events
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'eventUnlimited'::uuid
            ),
            'waitlist', (
                select coalesce(jsonb_agg(user_id order by user_id), '[]'::jsonb)
                from event_waitlist
                where event_id = :'eventUnlimited'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s","%s"],"waitlist":[]}',
        :'user2ID',
        :'user4ID'
    )::jsonb,
    'Moves the full waitlist into attendees when an unlimited event is left'
);

-- Should reject unknown attendee state
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventOK', :'user3ID'
    ),
    'user is not attending or waitlisted for this event',
    'Rejects leave requests for users without attendance state'
);

-- Should reject past events
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventPast', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects leave requests for past events'
);

-- Should reject waitlist leave requests for canceled events
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventCanceled', :'user4ID'
    ),
    'event not found or inactive',
    'Rejects waitlist leave requests for canceled events'
);

-- Should reject deleted events
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventDeleted', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects leave requests for deleted events'
);

-- Should reject events from inactive groups
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInactiveGroup', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects leave requests for inactive-group events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
