-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a110000-0000-0000-0000-000000000001'
\set eventCategoryID '4a110000-0000-0000-0000-000000000002'
\set eventID '4a110000-0000-0000-0000-000000000003'
\set groupCategoryID '4a110000-0000-0000-0000-000000000004'
\set groupID '4a110000-0000-0000-0000-000000000005'
\set invitedUserID '4a110000-0000-0000-0000-000000000006'

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
    'event-invitation-community',
    'Event Invitation Community',
    'Community for testing event invitation rejection',
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
);

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Invitation Group', 'invitation-group');

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
) values (
    :'eventID',
    'Free Event',
    'free-event',
    'Free event with invitation rejection',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    true,
    current_timestamp + interval '1 day'
);

-- Event invitation
insert into event_attendee (event_id, user_id, status)
values (:'eventID', :'invitedUserID', 'invitation-pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject pending invitations.
select lives_ok(
    format(
        $$
            select reject_event_attendee_invitation(%L::uuid, %L::uuid)
        $$,
        :'invitedUserID',
        :'eventID'
    ),
    'Should reject a pending event invitation'
);

select is(
    (select status from event_attendee where event_id = :'eventID' and user_id = :'invitedUserID'),
    'invitation-rejected',
    'Should persist rejected invitation status'
);

-- Should reject rejecting non-pending invitations.
select throws_ok(
    format(
        $$
            select reject_event_attendee_invitation(%L::uuid, %L::uuid)
        $$,
        :'invitedUserID',
        :'eventID'
    ),
    'pending event invitation not found',
    'Should reject rejecting non-pending invitations'
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
    format(
        $$
            values (
                'event_attendee_invitation_rejected',
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
        :'communityID',
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
