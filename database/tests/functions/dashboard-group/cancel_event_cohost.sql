-- Tests canceling approved event co-hosting.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID 'e50f0000-0000-0000-0000-000000000001'
\set approvedEventID 'e50f0000-0000-0000-0000-000000000002'
\set approvedInvitationID 'e50f0000-0000-0000-0000-000000000003'
\set cohostGroupID 'e50f0000-0000-0000-0000-000000000006'
\set communityID 'e50f0000-0000-0000-0000-000000000007'
\set eventCategoryID 'e50f0000-0000-0000-0000-00000000000a'
\set groupCategoryID 'e50f0000-0000-0000-0000-00000000000b'
\set groupID 'e50f0000-0000-0000-0000-00000000000c'
\set missingInvitationID 'e50f0000-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups, event and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'approvedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_user(:'actorUserID');

-- Approved co-hosting canceled by the success scenario
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id, invitation_id)
values ('2025-01-01 00:00:00+00', 'approved', :'approvedEventID', :'cohostGroupID', :'approvedInvitationID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel approved co-hosting on a published event
select is(
    cancel_event_cohost(:'actorUserID'::uuid, :'cohostGroupID'::uuid, :'approvedInvitationID'::uuid)::jsonb,
    jsonb_build_object(
        'cohost_group_id', :'cohostGroupID'::uuid,
        'event_id', :'approvedEventID'::uuid,
        'invitation_id', :'approvedInvitationID'::uuid,
        'owner_community_id', :'communityID'::uuid,
        'owner_group_id', :'groupID'::uuid
    ),
    'Should cancel approved co-hosting on a published event'
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
        :'approvedEventID'
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
        :'approvedEventID'
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
        :'approvedInvitationID'
    ),
    'Should audit cancellation on owner and co-host scopes'
);

-- Should reject missing invitations
select throws_ok(
    format('select cancel_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'actorUserID', :'cohostGroupID', :'missingInvitationID'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject missing invitations'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
