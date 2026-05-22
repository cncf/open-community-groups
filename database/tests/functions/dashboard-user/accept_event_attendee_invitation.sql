-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000002'
\set communityID '00000000-0000-0000-0000-000000000003'
\set eventCategoryID '00000000-0000-0000-0000-000000000004'
\set eventID '00000000-0000-0000-0000-000000000005'
\set groupID '00000000-0000-0000-0000-000000000006'
\set invitedUserID '00000000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Tech', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'G1', 'g1');

-- Users
insert into "user" (auth_hash, email, email_verified, name, user_id, username)
values ('hash-invited', 'invited@example.com', true, 'Invited', :'invitedUserID', 'invited');

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    capacity,
    payment_currency_code,
    published,
    starts_at
)
values (:'eventID', 'Free Event', 'free-event', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', 0, 'USD', true, current_timestamp + interval '1 day');

-- Event invitations
insert into event_attendee (event_id, user_id, manually_invited, status)
values (:'eventID', :'invitedUserID', true, 'invitation-pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept an invitation and return community scope.
select is(
    accept_event_attendee_invitation(:'invitedUserID', :'eventID'),
    :'communityID'::uuid,
    'Should return community id for notification context'
);

select is(
    (select status from event_attendee where event_id = :'eventID' and user_id = :'invitedUserID'),
    'confirmed',
    'Should confirm the attendee even when capacity is full'
);

select ok(
    (select manually_invited from event_attendee where event_id = :'eventID' and user_id = :'invitedUserID'),
    'Should keep the attendee marked as manually invited'
);

-- Should reject accepting non-pending invitations.
select throws_ok(
    $$ select accept_event_attendee_invitation(
        '00000000-0000-0000-0000-000000000007',
        '00000000-0000-0000-0000-000000000005'
    ) $$,
    'pending event invitation not found',
    'Should reject accepting non-pending invitations'
);

-- Should create the expected audit row.
select results_eq(
    $$
        select
            action,
            actor_user_id,
            community_id,
            event_id,
            group_id,
            resource_id,
            resource_type,
            details
        from audit_log
    $$,
    $$
        values (
            'event_attendee_invitation_accepted',
            '00000000-0000-0000-0000-000000000007'::uuid,
            '00000000-0000-0000-0000-000000000003'::uuid,
            '00000000-0000-0000-0000-000000000005'::uuid,
            '00000000-0000-0000-0000-000000000006'::uuid,
            '00000000-0000-0000-0000-000000000007'::uuid,
            'user',
            '{"event_id": "00000000-0000-0000-0000-000000000005", "user_id": "00000000-0000-0000-0000-000000000007"}'::jsonb
        )
    $$,
    'Should create the expected audit row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
