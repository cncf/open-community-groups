-- Tests rejecting event co-host invitations.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID 'e50e0000-0000-0000-0000-000000000001'
\set canceledEventID 'e50e0000-0000-0000-0000-000000000002'
\set canceledInvitationID 'e50e0000-0000-0000-0000-000000000003'
\set cohostGroupID 'e50e0000-0000-0000-0000-000000000004'
\set communityID 'e50e0000-0000-0000-0000-000000000005'
\set deletedEventID 'e50e0000-0000-0000-0000-000000000006'
\set deletedInvitationID 'e50e0000-0000-0000-0000-000000000007'
\set eventCategoryID 'e50e0000-0000-0000-0000-000000000008'
\set groupCategoryID 'e50e0000-0000-0000-0000-000000000009'
\set groupID 'e50e0000-0000-0000-0000-00000000000a'
\set missingInvitationID 'e50e0000-0000-0000-0000-00000000000b'
\set nonPendingEventID 'e50e0000-0000-0000-0000-00000000000c'
\set nonPendingInvitationID 'e50e0000-0000-0000-0000-00000000000d'
\set pendingEventID 'e50e0000-0000-0000-0000-00000000000e'
\set pendingInvitationID 'e50e0000-0000-0000-0000-00000000000f'
\set publishedEventID 'e50e0000-0000-0000-0000-000000000010'
\set publishedInvitationID 'e50e0000-0000-0000-0000-000000000011'
\set rotatedEventID 'e50e0000-0000-0000-0000-000000000012'
\set rotatedInvitationID 'e50e0000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups, events and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object('canceled', true));
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('deleted', true));
select fx_event(:'nonPendingEventID', :'groupID', :'eventCategoryID');
select fx_event(:'pendingEventID', :'groupID', :'eventCategoryID');
select fx_event(:'publishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'rotatedEventID', :'groupID', :'eventCategoryID');
select fx_user(:'actorUserID');

-- Pending invitation on a canceled event
insert into event_cohost (event_id, group_id, invitation_id)
values (:'canceledEventID', :'cohostGroupID', :'canceledInvitationID');

-- Pending invitation on a deleted event
insert into event_cohost (event_id, group_id, invitation_id)
values (:'deletedEventID', :'cohostGroupID', :'deletedInvitationID');

-- Invitation already approved
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id, invitation_id)
values ('2025-01-01 00:00:00+00', 'approved', :'nonPendingEventID', :'cohostGroupID', :'nonPendingInvitationID');

-- Pending invitation rejected by the success scenario
insert into event_cohost (event_id, group_id, invitation_id)
values (:'pendingEventID', :'cohostGroupID', :'pendingInvitationID');

-- Pending invitation on a published event
insert into event_cohost (event_id, group_id, invitation_id)
values (:'publishedEventID', :'cohostGroupID', :'publishedInvitationID');

-- Rejected invitation re-opened below with a rotated id
insert into event_cohost (event_cohost_status_id, event_id, group_id, invitation_id)
values ('rejected', :'rotatedEventID', :'cohostGroupID', :'rotatedInvitationID');

-- Re-invite the rejected co-host through the owner sync behavior, rotating its invitation id
select sync_event_cohosts(:'actorUserID'::uuid, :'groupID'::uuid, :'rotatedEventID'::uuid, array[:'cohostGroupID'::uuid], 0);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a pending invitation and return notification identifiers
select is(
    reject_event_cohost(:'actorUserID'::uuid, :'cohostGroupID'::uuid, :'pendingInvitationID'::uuid)::jsonb,
    jsonb_build_object(
        'cohost_group_id', :'cohostGroupID'::uuid,
        'event_id', :'pendingEventID'::uuid,
        'invitation_id', :'pendingInvitationID'::uuid,
        'owner_community_id', :'communityID'::uuid,
        'owner_group_id', :'groupID'::uuid
    ),
    'Should reject a pending invitation and return notification identifiers'
);

-- Should persist rejection evidence and advance revision
select results_eq(
    format(
        $$
            select
                e.cohosts_revision,
                ec.event_cohost_status_id,
                ec.responded_at,
                ec.responded_by
            from event_cohost ec
            join event e using (event_id)
            where ec.event_id = %L::uuid
        $$,
        :'pendingEventID'
    ),
    format(
        $$ values (1, 'rejected', current_timestamp, %L::uuid) $$,
        :'actorUserID'
    ),
    'Should persist rejection evidence and advance revision'
);

-- Should audit rejection on owner and co-host scopes
select results_eq(
    format(
        $$
            select action, actor_user_id, community_id, details, group_id
            from audit_log
            where event_id = %L::uuid
            and action = 'event_cohost_rejected'
            order by group_id
        $$,
        :'pendingEventID'
    ),
    format(
        $$
            with rejection as (
                select jsonb_build_object(
                    'cohost_group_id', %3$L::uuid,
                    'from_status', 'pending',
                    'invitation_id', %5$L::uuid,
                    'owner_group_id', %4$L::uuid,
                    'to_status', 'rejected'
                ) as details
            )
            select 'event_cohost_rejected', %1$L::uuid, %2$L::uuid, details, %3$L::uuid from rejection
            union all
            select 'event_cohost_rejected', %1$L::uuid, %2$L::uuid, details, %4$L::uuid from rejection
        $$,
        :'actorUserID',
        :'communityID',
        :'cohostGroupID',
        :'groupID',
        :'pendingInvitationID'
    ),
    'Should audit rejection on owner and co-host scopes'
);

-- Should reject missing invitations
select throws_ok(
    format('select reject_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'actorUserID', :'cohostGroupID', :'missingInvitationID'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject missing invitations'
);

-- Should reject invitations on deleted events
select throws_ok(
    format('select reject_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'actorUserID', :'cohostGroupID', :'deletedInvitationID'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject invitations on deleted events'
);

-- Should reject a stale invitation id after the co-host was re-invited
select throws_ok(
    format('select reject_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'actorUserID', :'cohostGroupID', :'rotatedInvitationID'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject a stale invitation id after the co-host was re-invited'
);

-- Should reject canceled events
select throws_ok(
    format('select reject_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'actorUserID', :'cohostGroupID', :'canceledInvitationID'),
    'OCG01',
    'event is canceled',
    'Should reject canceled events'
);

-- Should reject after publication
select throws_ok(
    format('select reject_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'actorUserID', :'cohostGroupID', :'publishedInvitationID'),
    'OCG01',
    'co-hosting can only be approved or rejected before the event is published',
    'Should reject after publication'
);

-- Should reject invitations that are no longer pending
select throws_ok(
    format('select reject_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'actorUserID', :'cohostGroupID', :'nonPendingInvitationID'),
    'OCG01',
    'co-hosting invitation is no longer pending',
    'Should reject invitations that are no longer pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
