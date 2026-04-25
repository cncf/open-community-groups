-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '00000000-0000-0000-0000-000000000031'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventApprovalDisabledID '00000000-0000-0000-0000-000000000046'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventFullID '00000000-0000-0000-0000-000000000042'
\set eventID '00000000-0000-0000-0000-000000000041'
\set eventInactiveGroupID '00000000-0000-0000-0000-000000000045'
\set eventPastID '00000000-0000-0000-0000-000000000047'
\set eventUnpublishedID '00000000-0000-0000-0000-000000000044'
\set groupID '00000000-0000-0000-0000-000000000021'
\set inactiveGroupID '00000000-0000-0000-0000-000000000022'
\set requesterID '00000000-0000-0000-0000-000000000032'
\set requester2ID '00000000-0000-0000-0000-000000000033'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (
    :'communityID',
    'test-community',
    'Test Community',
    'Desc',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Users
insert into "user" (user_id, auth_hash, email, username)
values
    (:'actorID', 'h', 'actor@test.com', 'actor'),
    (:'requesterID', 'h', 'requester@test.com', 'requester'),
    (:'requester2ID', 'h', 'requester2@test.com', 'requester2');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug, active)
values
    (:'groupID', :'communityID', :'categoryID', 'Group', 'group', true),
    (:'inactiveGroupID', :'communityID', :'categoryID', 'Inactive Group', 'inactive-group', false);

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
    capacity,
    attendee_approval_required,
    starts_at,
    ends_at
)
values
    (
        :'eventID',
        'Invite Event',
        'invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        2,
        true,
        null,
        null
    ),
    (
        :'eventFullID',
        'Full Invite Event',
        'full-invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        1,
        true,
        null,
        null
    ),
    (
        :'eventUnpublishedID',
        'Unpublished Invite Event',
        'unpublished-invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        null,
        true,
        null,
        null
    ),
    (
        :'eventInactiveGroupID',
        'Inactive Group Invite Event',
        'inactive-group-invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'inactiveGroupID',
        true,
        null,
        true,
        null,
        null
    ),
    (
        :'eventApprovalDisabledID',
        'Approval Disabled Event',
        'approval-disabled-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        null,
        false,
        null,
        null
    ),
    (
        :'eventPastID',
        'Past Invite Event',
        'past-invite-event',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        null,
        true,
        current_timestamp - interval '2 hours',
        current_timestamp - interval '1 hour'
    );

-- Invitation requests
insert into event_invitation_request (event_id, user_id)
values
    (:'eventID', :'requesterID'),
    (:'eventFullID', :'requesterID'),
    (:'eventUnpublishedID', :'requesterID'),
    (:'eventInactiveGroupID', :'requesterID'),
    (:'eventApprovalDisabledID', :'requesterID'),
    (:'eventPastID', :'requesterID');

-- Existing attendee that fills the second event
insert into event_attendee (event_id, user_id)
values (:'eventFullID', :'requester2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept a pending invitation request
select lives_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventID', :'requesterID'
    ),
    'Should accept a pending invitation request'
);

-- Should mark the request accepted
select results_eq(
    format(
        $$
            select status, reviewed_by is not null, reviewed_at is not null
            from event_invitation_request
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'requesterID'
    ),
    $$ values ('accepted'::text, true, true) $$,
    'Should mark the request accepted'
);

-- Should create a confirmed attendee row
select ok(
    exists(
        select 1
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'requesterID'::uuid
    ),
    'Should create a confirmed attendee row'
);

-- Should track the acceptance in the audit log
select ok(
    exists(
        select 1
        from audit_log
        where action = 'event_invitation_request_accepted'
        and actor_user_id = :'actorID'::uuid
        and event_id = :'eventID'::uuid
        and resource_id = :'requesterID'::uuid
    ),
    'Should track the acceptance in the audit log'
);

-- Should reject accepting when event capacity is full
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventFullID', :'requesterID'
    ),
    'event has reached capacity',
    'Should reject accepting when event capacity is full'
);

-- Should reject accepting when event is unpublished
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventUnpublishedID', :'requesterID'
    ),
    'event not found or inactive',
    'Should reject accepting when event is unpublished'
);

-- Should reject accepting when event belongs to an inactive group
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'inactiveGroupID', :'eventInactiveGroupID', :'requesterID'
    ),
    'event not found or inactive',
    'Should reject accepting when event belongs to an inactive group'
);

-- Should reject accepting when event approval is disabled
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventApprovalDisabledID', :'requesterID'
    ),
    'event not found or inactive',
    'Should reject accepting when event approval is disabled'
);

-- Should reject accepting when event is past
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventPastID', :'requesterID'
    ),
    'event not found or inactive',
    'Should reject accepting when event is past'
);

-- Should reject accepting an already reviewed request
select throws_ok(
    format(
        'select accept_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventID', :'requesterID'
    ),
    'pending invitation request not found',
    'Should reject accepting an already reviewed request'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
