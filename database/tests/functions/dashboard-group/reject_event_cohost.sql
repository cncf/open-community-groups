-- Tests rejecting event co-host invitations.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID 'e50e0000-0000-0000-0000-000000000001'
\set cohostGroupID 'e50e0000-0000-0000-0000-000000000004'
\set communityID 'e50e0000-0000-0000-0000-000000000005'
\set eventCategoryID 'e50e0000-0000-0000-0000-000000000008'
\set groupCategoryID 'e50e0000-0000-0000-0000-000000000009'
\set groupID 'e50e0000-0000-0000-0000-00000000000a'
\set missingInvitationID 'e50e0000-0000-0000-0000-00000000000b'
\set pendingEventID 'e50e0000-0000-0000-0000-00000000000e'
\set pendingInvitationID 'e50e0000-0000-0000-0000-00000000000f'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups, event and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'pendingEventID', :'groupID', :'eventCategoryID');
select fx_user(:'actorUserID');

-- Pending invitation rejected by the success scenario
insert into event_cohost (event_id, group_id, invitation_id)
values (:'pendingEventID', :'cohostGroupID', :'pendingInvitationID');

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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
