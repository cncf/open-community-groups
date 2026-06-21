-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000002'
\set allianceID '00000000-0000-0000-0000-000000000003'
\set eventCategoryID '00000000-0000-0000-0000-000000000004'
\set eventID '00000000-0000-0000-0000-000000000005'
\set groupID '00000000-0000-0000-0000-000000000006'
\set invitedUserID '00000000-0000-0000-0000-000000000008'

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

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'categoryID', 'G1', 'g1');

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
    published,
    starts_at
)
values (:'eventID', 'Free Event', 'free-event', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, current_timestamp + interval '1 day');

-- Event invitation
insert into event_attendee (event_id, user_id, status)
values (:'eventID', :'invitedUserID', 'invitation-pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject pending invitations.
select lives_ok(
    $$ select reject_event_attendee_invitation(
        '00000000-0000-0000-0000-000000000008',
        '00000000-0000-0000-0000-000000000005'
    ) $$,
    'Should reject a pending event invitation'
);

select is(
    (select status from event_attendee where event_id = :'eventID' and user_id = :'invitedUserID'),
    'invitation-rejected',
    'Should persist rejected invitation status'
);

-- Should reject rejecting non-pending invitations.
select throws_ok(
    $$ select reject_event_attendee_invitation(
        '00000000-0000-0000-0000-000000000008',
        '00000000-0000-0000-0000-000000000005'
    ) $$,
    'pending event invitation not found',
    'Should reject rejecting non-pending invitations'
);

-- Should create the expected audit row.
select results_eq(
    $$
        select
            action,
            actor_user_id,
            alliance_id,
            event_id,
            group_id,
            resource_id,
            resource_type,
            details
        from audit_log
    $$,
    $$
        values (
            'event_attendee_invitation_rejected',
            '00000000-0000-0000-0000-000000000008'::uuid,
            '00000000-0000-0000-0000-000000000003'::uuid,
            '00000000-0000-0000-0000-000000000005'::uuid,
            '00000000-0000-0000-0000-000000000006'::uuid,
            '00000000-0000-0000-0000-000000000008'::uuid,
            'user',
            '{"event_id": "00000000-0000-0000-0000-000000000005", "user_id": "00000000-0000-0000-0000-000000000008"}'::jsonb
        )
    $$,
    'Should create the expected audit row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
