-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '3a2d0000-0000-0000-0000-000000000001'
\set allianceID '3a2d0000-0000-0000-0000-000000000002'
\set eventCategoryID '3a2d0000-0000-0000-0000-000000000003'
\set eventID '3a2d0000-0000-0000-0000-000000000004'
\set groupCategoryID '3a2d0000-0000-0000-0000-000000000005'
\set groupID '3a2d0000-0000-0000-0000-000000000006'
\set requesterID '3a2d0000-0000-0000-0000-000000000007'

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
    'invitation-alliance',
    'Invitation Alliance',
    'A test alliance for invitations',
    'https://example.com/banner_mobile.png',
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
insert into "user" (user_id, auth_hash, email, username)
values
    (:'actorID', 'actor-hash', 'actor@test.com', 'actor'),
    (:'requesterID', 'requester-hash', 'requester@test.com', 'requester');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'groupCategoryID', 'Invite Group', 'invite-group');

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
    attendee_approval_required
) values (
    :'eventID',
    'Invite Event',
    'invite-event',
    'An event for invitation requests',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    true,
    true
);

-- Invitation request
insert into event_invitation_request (event_id, user_id)
values (:'eventID', :'requesterID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a pending invitation request
select lives_ok(
    format(
        'select reject_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventID', :'requesterID'
    ),
    'Should reject a pending invitation request'
);

-- Should mark the request rejected
select results_eq(
    'select status, reviewed_by is not null, reviewed_at is not null from event_invitation_request where event_id = ''' || :'eventID' || '''::uuid and user_id = ''' || :'requesterID' || '''::uuid',
    $$ values ('rejected'::text, true, true) $$,
    'Should mark the request rejected'
);

-- Should track the rejection in the audit log
select results_eq(
    $$
        select
            action,
            actor_user_id,
            alliance_id,
            details,
            event_id,
            group_id,
            resource_id,
            resource_type
        from audit_log
        where action = 'event_invitation_request_rejected'
    $$,
    format(
        $$
        values (
            'event_invitation_request_rejected',
            %L::uuid,
            %L::uuid,
            '{"event_id": "%s", "user_id": "%s"}'::jsonb,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'user'
        )
        $$,
        :'actorID', :'allianceID', :'eventID', :'requesterID', :'eventID', :'groupID', :'requesterID'
    ),
    'Should track the rejection in the audit log'
);

-- Should reject rejecting an already reviewed request
select throws_ok(
    format(
        'select reject_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventID', :'requesterID'
    ),
    'pending invitation request not found',
    'Should reject rejecting an already reviewed request'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
