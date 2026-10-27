-- Tests applying event co-host response transitions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(21);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID 'e5110000-0000-0000-0000-000000000001'
\set approvalEventID 'e5110000-0000-0000-0000-000000000002'
\set approvalInvitationID 'e5110000-0000-0000-0000-000000000003'
\set canceledEventID 'e5110000-0000-0000-0000-000000000004'
\set canceledInvitationID 'e5110000-0000-0000-0000-000000000005'
\set cancellationEventID 'e5110000-0000-0000-0000-000000000006'
\set cancellationInvitationID 'e5110000-0000-0000-0000-000000000007'
\set cohostGroupID 'e5110000-0000-0000-0000-000000000008'
\set communityID 'e5110000-0000-0000-0000-000000000009'
\set crossGroupEventID 'e5110000-0000-0000-0000-00000000000a'
\set crossGroupInvitationID 'e5110000-0000-0000-0000-00000000000b'
\set deletedEventID 'e5110000-0000-0000-0000-00000000000c'
\set deletedInvitationID 'e5110000-0000-0000-0000-00000000000d'
\set eventCategoryID 'e5110000-0000-0000-0000-00000000000e'
\set groupCategoryID 'e5110000-0000-0000-0000-00000000000f'
\set groupID 'e5110000-0000-0000-0000-000000000010'
\set missingInvitationID 'e5110000-0000-0000-0000-000000000011'
\set nonApprovedEventID 'e5110000-0000-0000-0000-000000000012'
\set nonApprovedInvitationID 'e5110000-0000-0000-0000-000000000013'
\set nonPendingEventID 'e5110000-0000-0000-0000-000000000014'
\set nonPendingInvitationID 'e5110000-0000-0000-0000-000000000015'
\set publishedEventID 'e5110000-0000-0000-0000-000000000016'
\set publishedInvitationID 'e5110000-0000-0000-0000-000000000017'
\set rejectionEventID 'e5110000-0000-0000-0000-000000000018'
\set rejectionInvitationID 'e5110000-0000-0000-0000-000000000019'
\set replayEventID 'e5110000-0000-0000-0000-00000000001a'
\set replayInvitationID 'e5110000-0000-0000-0000-00000000001b'
\set rotatedEventID 'e5110000-0000-0000-0000-00000000001c'
\set rotatedInvitationID 'e5110000-0000-0000-0000-00000000001d'
\set unrelatedGroupID 'e5110000-0000-0000-0000-00000000001e'

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
select fx_event(:'approvalEventID', :'groupID', :'eventCategoryID');
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object('canceled', true));
select fx_event(:'cancellationEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'crossGroupEventID', :'groupID', :'eventCategoryID');
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('deleted', true));
select fx_event(:'nonApprovedEventID', :'groupID', :'eventCategoryID');
select fx_event(:'nonPendingEventID', :'groupID', :'eventCategoryID');
select fx_event(:'publishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'rejectionEventID', :'groupID', :'eventCategoryID');
select fx_event(:'replayEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'rotatedEventID', :'groupID', :'eventCategoryID');
select fx_user(:'actorUserID');

-- Pending invitation approved by the approval scenario
insert into event_cohost (event_id, group_id, invitation_id)
values (:'approvalEventID', :'cohostGroupID', :'approvalInvitationID');

-- Pending invitation on a canceled event
insert into event_cohost (event_id, group_id, invitation_id)
values (:'canceledEventID', :'cohostGroupID', :'canceledInvitationID');

-- Approved co-hosting on a published event canceled by the cancellation scenario
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id, invitation_id)
values ('2025-01-01 00:00:00+00', 'approved', :'cancellationEventID', :'cohostGroupID', :'cancellationInvitationID');

-- Pending invitation addressed to the co-host group, used by another group
insert into event_cohost (event_id, group_id, invitation_id)
values (:'crossGroupEventID', :'cohostGroupID', :'crossGroupInvitationID');

-- Pending invitation on a deleted event
insert into event_cohost (event_id, group_id, invitation_id)
values (:'deletedEventID', :'cohostGroupID', :'deletedInvitationID');

-- Pending invitation that was never approved
insert into event_cohost (event_id, group_id, invitation_id)
values (:'nonApprovedEventID', :'cohostGroupID', :'nonApprovedInvitationID');

-- Invitation already approved
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id, invitation_id)
values ('2025-01-01 00:00:00+00', 'approved', :'nonPendingEventID', :'cohostGroupID', :'nonPendingInvitationID');

-- Pending invitation on a published event
insert into event_cohost (event_id, group_id, invitation_id)
values (:'publishedEventID', :'cohostGroupID', :'publishedInvitationID');

-- Pending invitation rejected by the rejection scenario
insert into event_cohost (event_id, group_id, invitation_id)
values (:'rejectionEventID', :'cohostGroupID', :'rejectionInvitationID');

-- Co-hosting already canceled, used by the replay scenario
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id, invitation_id)
values ('2025-01-01 00:00:00+00', 'canceled', :'replayEventID', :'cohostGroupID', :'replayInvitationID');

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
    transition_event_cohost(:'actorUserID'::uuid, :'cohostGroupID'::uuid, :'approvalInvitationID'::uuid, 'approved')::jsonb,
    jsonb_build_object(
        'cohost_group_id', :'cohostGroupID'::uuid,
        'event_id', :'approvalEventID'::uuid,
        'invitation_id', :'approvalInvitationID'::uuid,
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
        :'approvalEventID'
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
        :'approvalEventID'
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
        :'approvalInvitationID'
    ),
    'Should audit approval on owner and co-host scopes'
);

-- Should reject a pending invitation and return notification identifiers
select is(
    transition_event_cohost(:'actorUserID'::uuid, :'cohostGroupID'::uuid, :'rejectionInvitationID'::uuid, 'rejected')::jsonb,
    jsonb_build_object(
        'cohost_group_id', :'cohostGroupID'::uuid,
        'event_id', :'rejectionEventID'::uuid,
        'invitation_id', :'rejectionInvitationID'::uuid,
        'owner_community_id', :'communityID'::uuid,
        'owner_group_id', :'groupID'::uuid
    ),
    'Should reject a pending invitation and return notification identifiers'
);

-- Should persist rejection evidence without approval evidence and advance revision
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
        :'rejectionEventID'
    ),
    format(
        $$ values (null::timestamptz, 1, 'rejected', current_timestamp, %L::uuid) $$,
        :'actorUserID'
    ),
    'Should persist rejection evidence without approval evidence and advance revision'
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
        :'rejectionEventID'
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
        :'rejectionInvitationID'
    ),
    'Should audit rejection on owner and co-host scopes'
);

-- Should cancel approved co-hosting on a published event and return notification identifiers
select is(
    transition_event_cohost(:'actorUserID'::uuid, :'cohostGroupID'::uuid, :'cancellationInvitationID'::uuid, 'canceled')::jsonb,
    jsonb_build_object(
        'cohost_group_id', :'cohostGroupID'::uuid,
        'event_id', :'cancellationEventID'::uuid,
        'invitation_id', :'cancellationInvitationID'::uuid,
        'owner_community_id', :'communityID'::uuid,
        'owner_group_id', :'groupID'::uuid
    ),
    'Should cancel approved co-hosting on a published event and return notification identifiers'
);

-- Should keep approval evidence, record the response and advance revision
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
        :'cancellationEventID'
    ),
    format(
        $$ values ('2025-01-01 00:00:00+00'::timestamptz, 1, 'canceled', current_timestamp, %L::uuid) $$,
        :'actorUserID'
    ),
    'Should keep approval evidence, record the response and advance revision'
);

-- Should audit cancellation on owner and co-host scopes
select results_eq(
    format(
        $$
            select action, actor_user_id, community_id, details, group_id
            from audit_log
            where event_id = %L::uuid
            and action = 'event_cohost_canceled'
            order by group_id
        $$,
        :'cancellationEventID'
    ),
    format(
        $$
            with cancellation as (
                select jsonb_build_object(
                    'cohost_group_id', %3$L::uuid,
                    'from_status', 'approved',
                    'invitation_id', %5$L::uuid,
                    'owner_group_id', %4$L::uuid,
                    'to_status', 'canceled'
                ) as details
            )
            select 'event_cohost_canceled', %1$L::uuid, %2$L::uuid, details, %3$L::uuid from cancellation
            union all
            select 'event_cohost_canceled', %1$L::uuid, %2$L::uuid, details, %4$L::uuid from cancellation
        $$,
        :'actorUserID',
        :'communityID',
        :'cohostGroupID',
        :'groupID',
        :'cancellationInvitationID'
    ),
    'Should audit cancellation on owner and co-host scopes'
);

-- Should reject an invitation id rotated after rejection
select throws_ok(
    format('select transition_event_cohost(%L::uuid, %L::uuid, %L::uuid, %L)', :'actorUserID', :'cohostGroupID', :'rotatedInvitationID', 'approved'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject an invitation id rotated after rejection'
);

-- Should reject another group's invitation
select throws_ok(
    format('select transition_event_cohost(%L::uuid, %L::uuid, %L::uuid, %L)', :'actorUserID', :'unrelatedGroupID', :'crossGroupInvitationID', 'approved'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject another group''s invitation'
);

-- Should reject approvals after publication
select throws_ok(
    format('select transition_event_cohost(%L::uuid, %L::uuid, %L::uuid, %L)', :'actorUserID', :'cohostGroupID', :'publishedInvitationID', 'approved'),
    'OCG01',
    'co-hosting can only be approved or rejected before the event is published',
    'Should reject approvals after publication'
);

-- Should reject approvals for canceled events
select throws_ok(
    format('select transition_event_cohost(%L::uuid, %L::uuid, %L::uuid, %L)', :'actorUserID', :'cohostGroupID', :'canceledInvitationID', 'approved'),
    'OCG01',
    'event is canceled',
    'Should reject approvals for canceled events'
);

-- Should reject cancellations of co-hostings that are not approved
select throws_ok(
    format('select transition_event_cohost(%L::uuid, %L::uuid, %L::uuid, %L)', :'actorUserID', :'cohostGroupID', :'nonApprovedInvitationID', 'canceled'),
    'OCG01',
    'co-hosting is not approved',
    'Should reject cancellations of co-hostings that are not approved'
);

-- Should reject invitations on deleted events
select throws_ok(
    format('select transition_event_cohost(%L::uuid, %L::uuid, %L::uuid, %L)', :'actorUserID', :'cohostGroupID', :'deletedInvitationID', 'approved'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject invitations on deleted events'
);

-- Should reject invitations that are no longer pending
select throws_ok(
    format('select transition_event_cohost(%L::uuid, %L::uuid, %L::uuid, %L)', :'actorUserID', :'cohostGroupID', :'nonPendingInvitationID', 'approved'),
    'OCG01',
    'co-hosting invitation is no longer pending',
    'Should reject invitations that are no longer pending'
);

-- Should reject missing invitations
select throws_ok(
    format('select transition_event_cohost(%L::uuid, %L::uuid, %L::uuid, %L)', :'actorUserID', :'cohostGroupID', :'missingInvitationID', 'approved'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject missing invitations'
);

-- Should reject rejections after publication
select throws_ok(
    format('select transition_event_cohost(%L::uuid, %L::uuid, %L::uuid, %L)', :'actorUserID', :'cohostGroupID', :'publishedInvitationID', 'rejected'),
    'OCG01',
    'co-hosting can only be approved or rejected before the event is published',
    'Should reject rejections after publication'
);

-- Should reject rejections for canceled events
select throws_ok(
    format('select transition_event_cohost(%L::uuid, %L::uuid, %L::uuid, %L)', :'actorUserID', :'cohostGroupID', :'canceledInvitationID', 'rejected'),
    'OCG01',
    'event is canceled',
    'Should reject rejections for canceled events'
);

-- Should reject replaying a canceled co-hosting
select throws_ok(
    format('select transition_event_cohost(%L::uuid, %L::uuid, %L::uuid, %L)', :'actorUserID', :'cohostGroupID', :'replayInvitationID', 'canceled'),
    'OCG01',
    'co-hosting is not approved',
    'Should reject replaying a canceled co-hosting'
);

-- Should reject unsupported transitions
select throws_ok(
    format('select transition_event_cohost(%L::uuid, %L::uuid, %L::uuid, %L)', :'actorUserID', :'cohostGroupID', :'nonApprovedInvitationID', 'bogus'),
    'P0001',
    'unsupported co-host transition: bogus',
    'Should reject unsupported transitions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
