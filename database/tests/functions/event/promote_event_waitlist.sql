-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCappedID '00000000-0000-0000-0000-000000000041'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventFullID '00000000-0000-0000-0000-000000000042'
\set eventLimitedID '00000000-0000-0000-0000-000000000043'
\set eventUnlimitedID '00000000-0000-0000-0000-000000000044'
\set groupID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'
\set user3ID '00000000-0000-0000-0000-000000000033'
\set user4ID '00000000-0000-0000-0000-000000000034'
\set user5ID '00000000-0000-0000-0000-000000000035'
\set user6ID '00000000-0000-0000-0000-000000000036'
\set user7ID '00000000-0000-0000-0000-000000000037'
\set user8ID '00000000-0000-0000-0000-000000000038'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'test-community', 'Test Community', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'Active Group', 'active-group');

-- Users
insert into "user" (user_id, auth_hash, email, username)
values
    (:'user1ID', 'h', 'u1@test.com', 'u1'),
    (:'user2ID', 'h', 'u2@test.com', 'u2'),
    (:'user3ID', 'h', 'u3@test.com', 'u3'),
    (:'user4ID', 'h', 'u4@test.com', 'u4'),
    (:'user5ID', 'h', 'u5@test.com', 'u5'),
    (:'user6ID', 'h', 'u6@test.com', 'u6'),
    (:'user7ID', 'h', 'u7@test.com', 'u7'),
    (:'user8ID', 'h', 'u8@test.com', 'u8');

-- Events
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
    capacity,
    waitlist_enabled
)
values
    (:'eventCappedID', 'Capped', 'capped', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, 5, true),
    (:'eventFullID', 'Full', 'full', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, 1, true),
    (:'eventLimitedID', 'Limited', 'limited', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, 3, true),
    (:'eventUnlimitedID', 'Unlimited', 'unlimited', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, null, false);

-- Existing attendees
insert into event_attendee (event_id, user_id)
values
    (:'eventFullID', :'user1ID'),
    (:'eventLimitedID', :'user1ID');

-- Waitlist entries
insert into event_waitlist (event_id, user_id, created_at)
values
    (:'eventCappedID', :'user5ID', '2024-01-01 00:00:00+00'),
    (:'eventCappedID', :'user6ID', '2024-01-02 00:00:00+00'),
    (:'eventCappedID', :'user7ID', '2024-01-03 00:00:00+00'),
    (:'eventFullID', :'user2ID', '2024-01-01 00:00:00+00'),
    (:'eventLimitedID', :'user2ID', '2024-01-01 00:00:00+00'),
    (:'eventLimitedID', :'user3ID', '2024-01-02 00:00:00+00'),
    (:'eventLimitedID', :'user4ID', '2024-01-03 00:00:00+00'),
    (:'eventUnlimitedID', :'user7ID', '2024-01-01 00:00:00+00'),
    (:'eventUnlimitedID', :'user8ID', '2024-01-02 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore non-positive slot requests
select is(
    promote_event_waitlist(:'eventLimitedID'::uuid, 0),
    array[]::uuid[],
    'Returns an empty list when the requested slots are not positive'
);

-- Should leave state unchanged when the requested slots are not positive
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'eventLimitedID'::uuid
            ),
            'waitlist', (
                select jsonb_agg(user_id order by created_at asc, user_id asc)
                from event_waitlist
                where event_id = :'eventLimitedID'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s"],"waitlist":["%s","%s","%s"]}',
        :'user1ID',
        :'user2ID',
        :'user3ID',
        :'user4ID'
    )::jsonb,
    'Keeps attendees and waitlist unchanged when the requested slots are not positive'
);

-- Should return an empty list for an unknown event
select is(
    promote_event_waitlist('00000000-0000-0000-0000-999999999999'::uuid),
    array[]::uuid[],
    'Returns an empty list for an unknown event'
);

-- Should return an empty list when no seats are available
select is(
    promote_event_waitlist(:'eventFullID'::uuid),
    array[]::uuid[],
    'Returns an empty list when the event has no available seats'
);

-- Should promote the oldest waitlist entries up to the available capacity
select is(
    promote_event_waitlist(:'eventLimitedID'::uuid),
    array[:'user2ID'::uuid, :'user3ID'::uuid],
    'Promotes the oldest waitlist entries first when seats are available'
);

-- Should move promoted users into attendees and keep remaining waitlist order
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'eventLimitedID'::uuid
            ),
            'waitlist', (
                select jsonb_agg(user_id order by created_at asc, user_id asc)
                from event_waitlist
                where event_id = :'eventLimitedID'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s","%s","%s"],"waitlist":["%s"]}',
        :'user1ID',
        :'user2ID',
        :'user3ID',
        :'user4ID'
    )::jsonb,
    'Moves promoted users into attendees and leaves the remaining waitlist intact'
);

-- Should respect an explicit slots cap even when more seats are available
select is(
    promote_event_waitlist(:'eventCappedID'::uuid, 1),
    array[:'user5ID'::uuid],
    'Promotes only the requested number of waitlist entries when slots are capped'
);

-- Should promote all waitlist users for an unlimited-capacity event
select is(
    promote_event_waitlist(:'eventUnlimitedID'::uuid),
    array[:'user7ID'::uuid, :'user8ID'::uuid],
    'Promotes the full waitlist when the event has unlimited capacity'
);

-- Should clear the unlimited-capacity waitlist after promotion
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'eventUnlimitedID'::uuid
            ),
            'waitlist', (
                select coalesce(jsonb_agg(user_id order by created_at asc, user_id asc), '[]'::jsonb)
                from event_waitlist
                where event_id = :'eventUnlimitedID'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s","%s"],"waitlist":[]}',
        :'user7ID',
        :'user8ID'
    )::jsonb,
    'Clears the waitlist after promoting all users for an unlimited-capacity event'
);

-- Should keep working when trigger-based exclusivity is enabled
select is(
    promote_event_waitlist(:'eventCappedID'::uuid),
    array[:'user6ID'::uuid, :'user7ID'::uuid],
    'Promotes waitlist users successfully with attendee and waitlist exclusivity triggers enabled'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
