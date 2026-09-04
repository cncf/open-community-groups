-- Tests rejecting event invitation requests.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '3a2d0000-0000-0000-0000-000000000001'
\set communityID '3a2d0000-0000-0000-0000-000000000002'
\set eventCategoryID '3a2d0000-0000-0000-0000-000000000003'
\set eventID '3a2d0000-0000-0000-0000-000000000004'
\set groupCategoryID '3a2d0000-0000-0000-0000-000000000005'
\set groupID '3a2d0000-0000-0000-0000-000000000006'
\set requesterID '3a2d0000-0000-0000-0000-000000000007'
\set ticketTypeID '3a2d0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'actorID', jsonb_build_object('username', 'actor-reject-event-invitation-request'));
select fx_user(:'requesterID', jsonb_build_object('username', 'requester-reject-event-invitation-request'));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true
));

-- Ticket tier requested by the invitation requester
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object('seats_total', 10));

-- Invitation request
insert into event_invitation_request (event_id, event_ticket_type_id, user_id)
values (:'eventID', :'ticketTypeID', :'requesterID');

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
            community_id,
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
        :'actorID', :'communityID', :'eventID', :'requesterID', :'eventID', :'groupID', :'requesterID'
    ),
    'Should track the rejection in the audit log'
);

-- Should reject rejecting an already reviewed request
select throws_ok(
    format(
        'select reject_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'eventID', :'requesterID'
    ),
    'OCG01',
    'pending invitation request not found',
    'Should reject rejecting an already reviewed request'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
