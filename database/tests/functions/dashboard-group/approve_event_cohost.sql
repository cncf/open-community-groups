-- Tests approving event co-host invitations.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID 'e50d0000-0000-0000-0000-000000000001'
\set canceledEventID 'e50d0000-0000-0000-0000-000000000002'
\set canceledInvitationID 'e50d0000-0000-0000-0000-000000000003'
\set cohostGroupID 'e50d0000-0000-0000-0000-000000000004'
\set communityID 'e50d0000-0000-0000-0000-000000000005'
\set crossGroupEventID 'e50d0000-0000-0000-0000-000000000006'
\set crossGroupInvitationID 'e50d0000-0000-0000-0000-000000000007'
\set deletedEventID 'e50d0000-0000-0000-0000-000000000008'
\set deletedInvitationID 'e50d0000-0000-0000-0000-000000000009'
\set eventCategoryID 'e50d0000-0000-0000-0000-00000000000a'
\set groupCategoryID 'e50d0000-0000-0000-0000-00000000000b'
\set groupID 'e50d0000-0000-0000-0000-00000000000c'
\set missingInvitationID 'e50d0000-0000-0000-0000-00000000000d'
\set nonPendingEventID 'e50d0000-0000-0000-0000-00000000000e'
\set nonPendingInvitationID 'e50d0000-0000-0000-0000-00000000000f'
\set pendingEventID 'e50d0000-0000-0000-0000-000000000010'
\set pendingInvitationID 'e50d0000-0000-0000-0000-000000000011'
\set publishedEventID 'e50d0000-0000-0000-0000-000000000012'
\set publishedInvitationID 'e50d0000-0000-0000-0000-000000000013'
\set rotatedEventID 'e50d0000-0000-0000-0000-000000000014'
\set rotatedInvitationID 'e50d0000-0000-0000-0000-000000000015'
\set unrelatedGroupID 'e50d0000-0000-0000-0000-000000000016'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups, events and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'unrelatedGroupID', :'communityID', :'groupCategoryID');
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object('canceled', true));
select fx_event(:'crossGroupEventID', :'groupID', :'eventCategoryID');
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('deleted', true));
select fx_event(:'nonPendingEventID', :'groupID', :'eventCategoryID');
select fx_event(:'pendingEventID', :'groupID', :'eventCategoryID');
select fx_event(:'publishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'rotatedEventID', :'groupID', :'eventCategoryID');
select fx_user(:'actorUserID');

-- Pending invitation on a canceled event
insert into event_cohost (event_id, group_id, invitation_id)
values (:'canceledEventID', :'cohostGroupID', :'canceledInvitationID');

-- Pending invitation addressed to the co-host group, used by another group
insert into event_cohost (event_id, group_id, invitation_id)
values (:'crossGroupEventID', :'cohostGroupID', :'crossGroupInvitationID');

-- Pending invitation on a deleted event
insert into event_cohost (event_id, group_id, invitation_id)
values (:'deletedEventID', :'cohostGroupID', :'deletedInvitationID');

-- Invitation already approved
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id, invitation_id)
values ('2025-01-01 00:00:00+00', 'approved', :'nonPendingEventID', :'cohostGroupID', :'nonPendingInvitationID');

-- Pending invitation approved by the success scenario
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

-- Should approve a pending invitation and return notification identifiers
select is(
    approve_event_cohost(:'actorUserID'::uuid, :'cohostGroupID'::uuid, :'pendingInvitationID'::uuid)::jsonb,
    jsonb_build_object(
        'cohost_group_id', :'cohostGroupID'::uuid,
        'event_id', :'pendingEventID'::uuid,
        'invitation_id', :'pendingInvitationID'::uuid,
        'owner_community_id', :'communityID'::uuid,
        'owner_group_id', :'groupID'::uuid
    ),
    'Should approve a pending invitation and return notification identifiers'
);

-- Should persist approval evidence and advance revision
select results_eq(
    format(
        $$
            select
                ec.approved_at,
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
        $$ values (current_timestamp, 1, 'approved', current_timestamp, %L::uuid) $$,
        :'actorUserID'
    ),
    'Should persist approval evidence and advance revision'
);

-- Should audit approval on owner and co-host scopes
select results_eq(
    format(
        $$
            select action, actor_user_id, community_id, details, group_id
            from audit_log
            where event_id = %L::uuid
            and action = 'event_cohost_approved'
            order by group_id
        $$,
        :'pendingEventID'
    ),
    format(
        $$
            with approval as (
                select jsonb_build_object(
                    'cohost_group_id', %3$L::uuid,
                    'from_status', 'pending',
                    'invitation_id', %5$L::uuid,
                    'owner_group_id', %4$L::uuid,
                    'to_status', 'approved'
                ) as details
            )
            select 'event_cohost_approved', %1$L::uuid, %2$L::uuid, details, %3$L::uuid from approval
            union all
            select 'event_cohost_approved', %1$L::uuid, %2$L::uuid, details, %4$L::uuid from approval
        $$,
        :'actorUserID',
        :'communityID',
        :'cohostGroupID',
        :'groupID',
        :'pendingInvitationID'
    ),
    'Should audit approval on owner and co-host scopes'
);

-- Should reject missing invitations
select throws_ok(
    format('select approve_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'actorUserID', :'cohostGroupID', :'missingInvitationID'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject missing invitations'
);

-- Should reject another group's invitation
select throws_ok(
    format('select approve_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'actorUserID', :'unrelatedGroupID', :'crossGroupInvitationID'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject another group''s invitation'
);

-- Should reject invitations on deleted events
select throws_ok(
    format('select approve_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'actorUserID', :'cohostGroupID', :'deletedInvitationID'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject invitations on deleted events'
);

-- Should reject approving an invitation id rotated after rejection
select throws_ok(
    format('select approve_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'actorUserID', :'cohostGroupID', :'rotatedInvitationID'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject approving an invitation id rotated after rejection'
);

-- Should reject approvals for canceled events
select throws_ok(
    format('select approve_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'actorUserID', :'cohostGroupID', :'canceledInvitationID'),
    'OCG01',
    'event is canceled',
    'Should reject approvals for canceled events'
);

-- Should reject approvals after publication
select throws_ok(
    format('select approve_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'actorUserID', :'cohostGroupID', :'publishedInvitationID'),
    'OCG01',
    'co-hosting can only be approved or rejected before the event is published',
    'Should reject approvals after publication'
);

-- Should reject invitations that are no longer pending
select throws_ok(
    format('select approve_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'actorUserID', :'cohostGroupID', :'nonPendingInvitationID'),
    'OCG01',
    'co-hosting invitation is no longer pending',
    'Should reject invitations that are no longer pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
