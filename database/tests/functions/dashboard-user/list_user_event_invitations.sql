-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000002'
\set canceledEventID '00000000-0000-0000-0000-000000000008'
\set allianceID '00000000-0000-0000-0000-000000000003'
\set eventCategoryID '00000000-0000-0000-0000-000000000004'
\set eventID '00000000-0000-0000-0000-000000000005'
\set groupID '00000000-0000-0000-0000-000000000006'
\set inactiveGroupID '00000000-0000-0000-0000-000000000009'
\set inactiveGroupEventID '00000000-0000-0000-0000-000000000010'
\set acceptedUserID '00000000-0000-0000-0000-000000000011'
\set invitedUserID '00000000-0000-0000-0000-000000000007'
\set rejectedUserID '00000000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (alliance_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'allianceID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Group category
insert into group_category (group_category_id, name, alliance_id)
values (:'categoryID', 'Tech', :'allianceID');

-- Event category
insert into event_category (event_category_id, name, alliance_id)
values (:'eventCategoryID', 'General', :'allianceID');

-- Groups
insert into "group" (group_id, alliance_id, group_category_id, name, slug, active)
values
    (:'groupID', :'allianceID', :'categoryID', 'G1', 'g1', true),
    (:'inactiveGroupID', :'allianceID', :'categoryID', 'G2', 'g2', false);

-- Users
insert into "user" (auth_hash, email, email_verified, name, user_id, username)
values
    ('hash-invited', 'invited@example.com', true, 'Invited', :'invitedUserID', 'invited'),
    ('hash-accepted', 'accepted@example.com', true, 'Accepted', :'acceptedUserID', 'accepted'),
    ('hash-rejected', 'rejected@example.com', true, 'Rejected', :'rejectedUserID', 'rejected');

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
)
values
    (:'eventID', 'Future Event', 'future-event', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', 'USD', true, false, '2099-01-02 10:00:00+00'),
    (:'canceledEventID', 'Canceled Event', 'canceled-event', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', 'USD', true, true, '2099-01-03 10:00:00+00'),
    (:'inactiveGroupEventID', 'Inactive Group Event', 'inactive-event', 'd', 'UTC', :'eventCategoryID', 'in-person', :'inactiveGroupID', 'USD', true, false, '2099-01-04 10:00:00+00');

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
    '[
        {"alliance_display_name": "C1", "alliance_name": "c1", "event_id": "00000000-0000-0000-0000-000000000005", "event_name": "Future Event", "group_name": "G1", "timezone": "UTC", "created_at": 1704189600, "starts_at": 4071031200}
    ]'::jsonb,
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
