-- Tests rejecting event invitation requests.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '3a2d0000-0000-0000-0000-000000000001'
\set canceledEventID '3a2d0000-0000-0000-0000-000000000002'
\set canceledTicketTypeID '3a2d0000-0000-0000-0000-000000000003'
\set communityID '3a2d0000-0000-0000-0000-000000000004'
\set crossGroupRequesterID '3a2d0000-0000-0000-0000-000000000005'
\set eventCategoryID '3a2d0000-0000-0000-0000-000000000006'
\set eventID '3a2d0000-0000-0000-0000-000000000007'
\set groupCategoryID '3a2d0000-0000-0000-0000-000000000008'
\set groupID '3a2d0000-0000-0000-0000-000000000009'
\set otherGroupID '3a2d0000-0000-0000-0000-00000000000a'
\set requesterID '3a2d0000-0000-0000-0000-00000000000b'
\set reviewedRequesterID '3a2d0000-0000-0000-0000-00000000000c'
\set ticketTypeID '3a2d0000-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group that does not own the event
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'actorID', jsonb_build_object('username', 'actor-reject-event-invitation-request'));
select fx_user(:'crossGroupRequesterID');
select fx_user(:'requesterID', jsonb_build_object('username', 'requester-reject-event-invitation-request'));
select fx_user(:'reviewedRequesterID');

-- Canceled event that no longer accepts request reviews
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'canceled', true
));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true
));

-- Ticket tier requested on the canceled event
select fx_event_ticket_type(:'canceledTicketTypeID', :'canceledEventID', jsonb_build_object('seats_total', 10));

-- Ticket tier requested by the invitation requesters
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object('seats_total', 10));

-- Pending invitation request on the canceled event
insert into event_invitation_request (event_id, event_ticket_type_id, status, user_id)
values (:'canceledEventID', :'canceledTicketTypeID', 'pending', :'requesterID');

-- Pending invitation request targeted through another group
insert into event_invitation_request (event_id, event_ticket_type_id, status, user_id)
values (:'eventID', :'ticketTypeID', 'pending', :'crossGroupRequesterID');

-- Pending invitation request rejected by the success scenario
insert into event_invitation_request (event_id, event_ticket_type_id, status, user_id)
values (:'eventID', :'ticketTypeID', 'pending', :'requesterID');

-- Invitation request already rejected
insert into event_invitation_request (event_id, event_ticket_type_id, status, user_id, reviewed_at, reviewed_by)
values (:'eventID', :'ticketTypeID', 'rejected', :'reviewedRequesterID', '2025-01-01 00:00:00+00', :'actorID');

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
    format(
        $$
            select status, reviewed_at, reviewed_by
            from event_invitation_request
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID', :'requesterID'
    ),
    format(
        $$ values ('rejected'::text, current_timestamp, %L::uuid) $$,
        :'actorID'
    ),
    'Should mark the request rejected'
);

-- Should track the rejection in the audit log
select results_eq(
    format(
        $$
            select
                action,
                actor_user_id,
                actor_username,
                community_id,
                details,
                event_id,
                group_id,
                resource_id,
                resource_type
            from audit_log
            where action = 'event_invitation_request_rejected'
            and resource_id = %L::uuid
        $$,
        :'requesterID'
    ),
    format(
        $$
        values (
            'event_invitation_request_rejected',
            %L::uuid,
            'actor-reject-event-invitation-request',
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
        :'actorID', :'groupID', :'eventID', :'reviewedRequesterID'
    ),
    'OCG01',
    'pending invitation request not found',
    'Should reject rejecting an already reviewed request'
);

-- Should reject requests for canceled events
select throws_ok(
    format(
        'select reject_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'groupID', :'canceledEventID', :'requesterID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject requests for canceled events'
);

-- Should reject requests for events owned by another group
select throws_ok(
    format(
        'select reject_event_invitation_request(%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
        :'actorID', :'otherGroupID', :'eventID', :'crossGroupRequesterID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject requests for events owned by another group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
