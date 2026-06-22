-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '4a020000-0000-0000-0000-000000000001'
\set eventCategoryID '4a020000-0000-0000-0000-000000000002'
\set eventID '4a020000-0000-0000-0000-000000000003'
\set groupCategoryID '4a020000-0000-0000-0000-000000000004'
\set groupID '4a020000-0000-0000-0000-000000000005'
\set invitedUserID '4a020000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'event-invitation-alliance',
    'Event Invitation Alliance',
    'Alliance for testing event invitation acceptance',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'General');

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
);

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'groupCategoryID', 'Invitation Group', 'invitation-group');

-- Event
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    capacity,
    payment_currency_code,
    published,
    starts_at,
    timezone
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Free Event',
    'free-event',
    'Free event with invitation acceptance',
    0,
    'USD',
    true,
    current_timestamp + interval '1 day',
    'UTC'
);

-- Event invitations
insert into event_attendee (event_id, user_id, manually_invited, status)
values (:'eventID', :'invitedUserID', true, 'invitation-pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept an invitation and return alliance scope.
select is(
    accept_event_attendee_invitation(:'invitedUserID', :'eventID'),
    :'allianceID'::uuid,
    'Should return alliance id for notification context'
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
    format(
        $$
            select accept_event_attendee_invitation(%L::uuid, %L::uuid)
        $$,
        :'invitedUserID',
        :'eventID'
    ),
    'pending event invitation not found',
    'Should reject accepting non-pending invitations'
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
    format(
        $$
            values (
                'event_attendee_invitation_accepted',
                %L::uuid,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                'user',
                '{"event_id": "%s", "user_id": "%s"}'::jsonb
            )
        $$,
        :'invitedUserID',
        :'allianceID',
        :'eventID',
        :'groupID',
        :'invitedUserID',
        :'eventID',
        :'invitedUserID'
    ),
    'Should create the expected audit row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
