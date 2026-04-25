-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '00000000-0000-0000-0000-000000000031'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventFullID '00000000-0000-0000-0000-000000000042'
\set eventID '00000000-0000-0000-0000-000000000041'
\set groupID '00000000-0000-0000-0000-000000000021'
\set requesterID '00000000-0000-0000-0000-000000000032'
\set requester2ID '00000000-0000-0000-0000-000000000033'

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

-- Users
insert into "user" (user_id, auth_hash, email, username)
values
    (:'actorID', 'h', 'actor@test.com', 'actor'),
    (:'requesterID', 'h', 'requester@test.com', 'requester'),
    (:'requester2ID', 'h', 'requester2@test.com', 'requester2');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'Group', 'group');

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
    attendee_approval_required
)
values
    (:'eventID', 'Invite Event', 'invite-event', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, 2, true),
    (:'eventFullID', 'Full Invite Event', 'full-invite-event', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, 1, true);

-- Invitation requests
insert into event_invitation_request (event_id, user_id)
values
    (:'eventID', :'requesterID'),
    (:'eventFullID', :'requesterID');

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
    'select status, reviewed_by is not null, reviewed_at is not null from event_invitation_request where event_id = ''' || :'eventID' || '''::uuid and user_id = ''' || :'requesterID' || '''::uuid',
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
