-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedUserID '4a0b0000-0000-0000-0000-000000000001'
\set canceledEventID '4a0b0000-0000-0000-0000-000000000002'
\set communityID '4a0b0000-0000-0000-0000-000000000003'
\set eventCategoryID '4a0b0000-0000-0000-0000-000000000004'
\set eventID '4a0b0000-0000-0000-0000-000000000005'
\set groupCategoryID '4a0b0000-0000-0000-0000-000000000006'
\set groupID '4a0b0000-0000-0000-0000-000000000007'
\set inactiveGroupEventID '4a0b0000-0000-0000-0000-000000000008'
\set inactiveGroupID '4a0b0000-0000-0000-0000-000000000009'
\set invitedUserID '4a0b0000-0000-0000-0000-000000000010'
\set rejectedUserID '4a0b0000-0000-0000-0000-000000000011'

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
    'event-invitations-community',
    'Event Invitations Community',
    'Community for testing event invitation listings',
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
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values (
    :'invitedUserID',
    'hash-invited',
    'invited@example.com',
    true,
    'invited',
    'Invited User'
), (
    :'acceptedUserID',
    'hash-accepted',
    'accepted@example.com',
    true,
    'accepted',
    'Accepted User'
), (
    :'rejectedUserID',
    'hash-rejected',
    'rejected@example.com',
    true,
    'rejected',
    'Rejected User'
);

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug, active)
values
    (:'groupID', :'communityID', :'groupCategoryID', 'Event Invitations Group', 'events', true),
    (:'inactiveGroupID', :'communityID', :'groupCategoryID', 'Inactive Group', 'inactive', false);

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
    payment_currency_code,
    published,
    canceled,
    starts_at
) values (
    :'eventID',
    'Future Event',
    'future-event',
    'Future event with pending invitations',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    false,
    '2099-01-02 10:00:00+00'
), (
    :'canceledEventID',
    'Canceled Event',
    'canceled-event',
    'Canceled event with ignored invitations',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    true,
    '2099-01-03 10:00:00+00'
), (
    :'inactiveGroupEventID',
    'Inactive Group Event',
    'inactive-event',
    'Inactive group event with ignored invitations',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'inactiveGroupID',
    'USD',
    true,
    false,
    '2099-01-04 10:00:00+00'
);

-- Event invitation states
insert into event_attendee (event_id, user_id, status, created_at)
values
    (:'eventID', :'invitedUserID', 'invitation-pending', '2024-01-02 10:00:00+00'),
    (:'canceledEventID', :'invitedUserID', 'invitation-pending', '2024-01-03 10:00:00+00'),
    (:'inactiveGroupEventID', :'invitedUserID', 'invitation-pending', '2024-01-04 10:00:00+00'),
    (:'eventID', :'acceptedUserID', 'confirmed', '2024-01-05 10:00:00+00'),
    (:'eventID', :'rejectedUserID', 'invitation-rejected', '2024-01-06 10:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list active pending event invitations for a user.
select is(
    list_user_event_invitations(:'invitedUserID'::uuid)::jsonb,
    format(
        $json$
            [
                {
                    "community_display_name": "Event Invitations Community",
                    "community_name": "event-invitations-community",
                    "event_id": "%s",
                    "event_name": "Future Event",
                    "group_name": "Event Invitations Group",
                    "timezone": "UTC",
                    "created_at": 1704189600,
                    "starts_at": 4071031200
                }
            ]
        $json$,
        :'eventID'
    )::jsonb,
    'Should list active pending event invitations for the user'
);

-- Should not list accepted event invitations.
select is(
    list_user_event_invitations(:'acceptedUserID'::uuid)::text,
    '[]',
    'Should not list accepted event invitations'
);

-- Should not list rejected event invitations.
select is(
    list_user_event_invitations(:'rejectedUserID'::uuid)::text,
    '[]',
    'Should not list rejected event invitations'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
