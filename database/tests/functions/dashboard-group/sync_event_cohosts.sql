-- Tests synchronizing owner-selected event co-hosts.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(22);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID 'e50c0000-0000-0000-0000-000000000001'
\set addEventID 'e50c0000-0000-0000-0000-000000000002'
\set addGroupID 'e50c0000-0000-0000-0000-000000000003'
\set canceledEventID 'e50c0000-0000-0000-0000-000000000004'
\set canceledReinviteGroupID 'e50c0000-0000-0000-0000-000000000005'
\set canceledReinviteInvitationID 'e50c0000-0000-0000-0000-000000000006'
\set cohostResponderUserID 'e50c0000-0000-0000-0000-000000000007'
\set communityID 'e50c0000-0000-0000-0000-000000000008'
\set eventCategoryID 'e50c0000-0000-0000-0000-00000000000a'
\set groupCategoryID 'e50c0000-0000-0000-0000-00000000000b'
\set groupID 'e50c0000-0000-0000-0000-00000000000c'
\set inactiveCommunityGroupCategoryID 'e50c0000-0000-0000-0000-00000000000d'
\set inactiveCommunityGroupID 'e50c0000-0000-0000-0000-00000000000e'
\set inactiveCommunityID 'e50c0000-0000-0000-0000-00000000000f'
\set inactiveExistingEventID 'e50c0000-0000-0000-0000-000000000010'
\set inactiveExistingGroupID 'e50c0000-0000-0000-0000-000000000011'
\set inactiveNewGroupID 'e50c0000-0000-0000-0000-000000000012'
\set keepAddedGroupID 'e50c0000-0000-0000-0000-000000000014'
\set missingGroupID 'e50c0000-0000-0000-0000-000000000015'
\set nullEntryEventID 'e50c0000-0000-0000-0000-000000000016'
\set nullEntryGroupID 'e50c0000-0000-0000-0000-000000000017'
\set otherGroupID 'e50c0000-0000-0000-0000-000000000018'
\set overflowGroup01ID 'e50c0000-0000-0000-0000-000000000019'
\set overflowGroup02ID 'e50c0000-0000-0000-0000-00000000001a'
\set overflowGroup03ID 'e50c0000-0000-0000-0000-00000000001b'
\set overflowGroup04ID 'e50c0000-0000-0000-0000-00000000001c'
\set overflowGroup05ID 'e50c0000-0000-0000-0000-00000000001d'
\set overflowGroup06ID 'e50c0000-0000-0000-0000-00000000001e'
\set overflowGroup07ID 'e50c0000-0000-0000-0000-00000000001f'
\set overflowGroup08ID 'e50c0000-0000-0000-0000-000000000020'
\set overflowGroup09ID 'e50c0000-0000-0000-0000-000000000021'
\set overflowGroup10ID 'e50c0000-0000-0000-0000-000000000022'
\set overflowGroup11ID 'e50c0000-0000-0000-0000-000000000023'
\set publishedAddGroupID 'e50c0000-0000-0000-0000-000000000024'
\set publishedEventID 'e50c0000-0000-0000-0000-000000000025'
\set publishedExistingGroupID 'e50c0000-0000-0000-0000-000000000026'
\set reinviteEventID 'e50c0000-0000-0000-0000-000000000027'
\set rejectedReinviteGroupID 'e50c0000-0000-0000-0000-000000000028'
\set rejectedReinviteInvitationID 'e50c0000-0000-0000-0000-000000000029'
\set removeEventID 'e50c0000-0000-0000-0000-00000000002a'
\set removeGroupID 'e50c0000-0000-0000-0000-00000000002b'
\set removeInvitationID 'e50c0000-0000-0000-0000-00000000002c'
\set removedReinviteGroupID 'e50c0000-0000-0000-0000-00000000002d'
\set removedReinviteInvitationID 'e50c0000-0000-0000-0000-00000000002e'
\set staleEventID 'e50c0000-0000-0000-0000-00000000002f'
\set unchangedEventID 'e50c0000-0000-0000-0000-000000000030'
\set unchangedFirstGroupID 'e50c0000-0000-0000-0000-000000000031'
\set unchangedSecondGroupID 'e50c0000-0000-0000-0000-000000000032'
\set validationEventID 'e50c0000-0000-0000-0000-000000000033'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community owning the event groups
select fx_community(:'communityID');

-- Inactive community owning an otherwise active co-host group
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false));

-- Owner-side actor syncing the co-hosts
select fx_user(:'actorUserID', jsonb_build_object('username', 'sync-cohosts-actor'));

-- Co-host group member who responded to earlier invitations
select fx_user(:'cohostResponderUserID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category in the active community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category in the inactive community
select fx_group_category(:'inactiveCommunityGroupCategoryID', :'inactiveCommunityID');

-- Owner group of every event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group added by the add scenario
select fx_group(:'addGroupID', :'communityID', :'groupCategoryID');

-- Canceled co-host group re-invited by the re-invite scenario
select fx_group(:'canceledReinviteGroupID', :'communityID', :'groupCategoryID');

-- Active group in the inactive community
select fx_group(:'inactiveCommunityGroupID', :'inactiveCommunityID', :'inactiveCommunityGroupCategoryID');

-- Inactive group already approved as a co-host
select fx_group(:'inactiveExistingGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Inactive group requested as a new co-host
select fx_group(:'inactiveNewGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Group added next to the existing inactive co-host
select fx_group(:'keepAddedGroupID', :'communityID', :'groupCategoryID');

-- Group added by the null entry scenario
select fx_group(:'nullEntryGroupID', :'communityID', :'groupCategoryID');

-- Other group of the same community used as a cross-group caller
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Eleven valid groups used by the too-many-co-hosts scenario
select fx_group(:'overflowGroup01ID', :'communityID', :'groupCategoryID');
select fx_group(:'overflowGroup02ID', :'communityID', :'groupCategoryID');
select fx_group(:'overflowGroup03ID', :'communityID', :'groupCategoryID');
select fx_group(:'overflowGroup04ID', :'communityID', :'groupCategoryID');
select fx_group(:'overflowGroup05ID', :'communityID', :'groupCategoryID');
select fx_group(:'overflowGroup06ID', :'communityID', :'groupCategoryID');
select fx_group(:'overflowGroup07ID', :'communityID', :'groupCategoryID');
select fx_group(:'overflowGroup08ID', :'communityID', :'groupCategoryID');
select fx_group(:'overflowGroup09ID', :'communityID', :'groupCategoryID');
select fx_group(:'overflowGroup10ID', :'communityID', :'groupCategoryID');
select fx_group(:'overflowGroup11ID', :'communityID', :'groupCategoryID');

-- Group requested as an addition to the published event
select fx_group(:'publishedAddGroupID', :'communityID', :'groupCategoryID');

-- Group already approved on the published event
select fx_group(:'publishedExistingGroupID', :'communityID', :'groupCategoryID');

-- Rejected co-host group re-invited by the re-invite scenario
select fx_group(:'rejectedReinviteGroupID', :'communityID', :'groupCategoryID');

-- Approved co-host group removed by the removal scenario
select fx_group(:'removeGroupID', :'communityID', :'groupCategoryID');

-- Removed co-host group re-invited by the re-invite scenario
select fx_group(:'removedReinviteGroupID', :'communityID', :'groupCategoryID');

-- First approved co-host group of the unchanged scenario
select fx_group(:'unchangedFirstGroupID', :'communityID', :'groupCategoryID');

-- Second approved co-host group of the unchanged scenario
select fx_group(:'unchangedSecondGroupID', :'communityID', :'groupCategoryID');

-- Event receiving a first co-host
select fx_event(:'addEventID', :'groupID', :'eventCategoryID');

-- Canceled event
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object('canceled', true));

-- Event with an approved co-host group that is now inactive
select fx_event(:'inactiveExistingEventID', :'groupID', :'eventCategoryID');

-- Event receiving a selection with a null entry
select fx_event(:'nullEntryEventID', :'groupID', :'eventCategoryID');

-- Published event with an approved co-host
select fx_event(:'publishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Event with closed invitations to re-open
select fx_event(:'reinviteEventID', :'groupID', :'eventCategoryID');

-- Event with an approved co-host to remove
select fx_event(:'removeEventID', :'groupID', :'eventCategoryID');

-- Event whose co-host revision moved past the editor's copy
select fx_event(:'staleEventID', :'groupID', :'eventCategoryID', jsonb_build_object('cohosts_revision', 2));

-- Published event with two approved co-hosts resubmitted unchanged
select fx_event(:'unchangedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Event used by the request validation rejections
select fx_event(:'validationEventID', :'groupID', :'eventCategoryID');

-- Approved co-host whose group became inactive
insert into event_cohost (
    event_cohost_status_id,
    event_id,
    group_id,

    approved_at,
    responded_at,
    responded_by
) values (
    'approved',
    :'inactiveExistingEventID',
    :'inactiveExistingGroupID',

    '2025-01-01 00:00:00+00',
    '2025-01-01 00:00:00+00',
    :'cohostResponderUserID'
);

-- Approved co-host of the published event
insert into event_cohost (
    event_cohost_status_id,
    event_id,
    group_id,

    approved_at,
    responded_at,
    responded_by
) values (
    'approved',
    :'publishedEventID',
    :'publishedExistingGroupID',

    '2025-01-01 00:00:00+00',
    '2025-01-01 00:00:00+00',
    :'cohostResponderUserID'
);

-- Canceled, rejected and removed invitations to re-open
insert into event_cohost (
    event_cohost_status_id,
    event_id,
    group_id,
    invitation_id,
    invited_at,

    approved_at,
    responded_at,
    responded_by
) values
    ('canceled', :'reinviteEventID', :'canceledReinviteGroupID', :'canceledReinviteInvitationID', '2025-01-01 00:00:00+00', '2025-01-01 00:00:00+00', '2025-01-02 00:00:00+00', :'cohostResponderUserID'),
    ('rejected', :'reinviteEventID', :'rejectedReinviteGroupID', :'rejectedReinviteInvitationID', '2025-01-01 00:00:00+00', null, '2025-01-02 00:00:00+00', :'cohostResponderUserID'),
    ('removed', :'reinviteEventID', :'removedReinviteGroupID', :'removedReinviteInvitationID', '2025-01-01 00:00:00+00', '2025-01-01 00:00:00+00', '2025-01-02 00:00:00+00', :'actorUserID');

-- Approved co-host to remove
insert into event_cohost (
    event_cohost_status_id,
    event_id,
    group_id,
    invitation_id,
    invited_at,
    updated_at,

    approved_at,
    invited_by,
    responded_at,
    responded_by
) values (
    'approved',
    :'removeEventID',
    :'removeGroupID',
    :'removeInvitationID',
    '2025-01-01 00:00:00+00',
    '2025-01-01 00:00:00+00',

    '2025-01-01 00:00:00+00',
    :'actorUserID',
    '2025-01-01 00:00:00+00',
    :'cohostResponderUserID'
);

-- Approved co-hosts of the published event resubmitted unchanged
insert into event_cohost (
    event_cohost_status_id,
    event_id,
    group_id,

    approved_at,
    responded_at,
    responded_by
) values
    ('approved', :'unchangedEventID', :'unchangedFirstGroupID', '2025-01-01 00:00:00+00', '2025-01-01 00:00:00+00', :'cohostResponderUserID'),
    ('approved', :'unchangedEventID', :'unchangedSecondGroupID', '2025-01-01 00:00:00+00', '2025-01-01 00:00:00+00', :'cohostResponderUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Add a first co-host
select sync_event_cohosts(
    :'actorUserID'::uuid,
    :'groupID'::uuid,
    :'addEventID'::uuid,
    array[:'addGroupID'::uuid],
    0
) as "addResult" \gset

-- Should add a co-host and return the full reference shape
select is(
    :'addResult'::jsonb,
    (
        select jsonb_build_object(
            'added', jsonb_build_array(jsonb_build_object(
                'cohost_group_id', ec.group_id,
                'event_id', ec.event_id,
                'invitation_id', ec.invitation_id
            )),
            'removed', '[]'::jsonb,
            'revision', 1
        )
        from event_cohost ec
        where ec.event_id = :'addEventID'::uuid
        and ec.group_id = :'addGroupID'::uuid
    ),
    'Should add a co-host and return the full reference shape'
);

-- Should audit invitations on owner and co-host scopes
select results_eq(
    format(
        $$
            select action, actor_user_id, actor_username, community_id, details, group_id
            from audit_log
            where event_id = %L::uuid
            and action = 'event_cohost_invited'
            order by group_id
        $$,
        :'addEventID'
    ),
    format(
        $$
            with invitation as (
                select jsonb_build_object(
                    'cohost_group_id', %3$L::uuid,
                    'from_status', null,
                    'invitation_id', invitation_id,
                    'owner_group_id', %4$L::uuid,
                    'to_status', 'pending'
                ) as details
                from event_cohost
                where event_id = %5$L::uuid
            )
            select 'event_cohost_invited', %1$L::uuid, 'sync-cohosts-actor', %2$L::uuid, details, %3$L::uuid from invitation
            union all
            select 'event_cohost_invited', %1$L::uuid, 'sync-cohosts-actor', %2$L::uuid, details, %4$L::uuid from invitation
        $$,
        :'actorUserID',
        :'communityID',
        :'addGroupID',
        :'groupID',
        :'addEventID'
    ),
    'Should audit invitations on owner and co-host scopes'
);

-- Should persist the added row as pending
select results_eq(
    format(
        $$
            select
                e.cohosts_revision,
                ec.event_cohost_status_id,
                ec.invited_at,
                ec.approved_at,
                ec.invited_by,
                ec.responded_at,
                ec.responded_by
            from event_cohost ec
            join event e using (event_id)
            where ec.event_id = %L::uuid
        $$,
        :'addEventID'
    ),
    format(
        $$
            values (
                1,
                'pending',
                current_timestamp,
                null::timestamptz,
                %L::uuid,
                null::timestamptz,
                null::uuid
            )
        $$,
        :'actorUserID'
    ),
    'Should persist the added row as pending'
);

-- Should allow unchanged published co-host selections
select is(
    sync_event_cohosts(
        :'actorUserID'::uuid,
        :'groupID'::uuid,
        :'publishedEventID'::uuid,
        array[:'publishedExistingGroupID'::uuid],
        0
    )::jsonb,
    '{"added":[],"removed":[],"revision":0}'::jsonb,
    'Should allow unchanged published co-host selections'
);

-- Submit a selection with a null entry
select sync_event_cohosts(
    :'actorUserID'::uuid,
    :'groupID'::uuid,
    :'nullEntryEventID'::uuid,
    array[null, :'nullEntryGroupID'::uuid],
    0
) as "nullEntryResult" \gset

-- Should ignore null co-host entries
select is(
    :'nullEntryResult'::jsonb,
    (
        select jsonb_build_object(
            'added', jsonb_build_array(jsonb_build_object(
                'cohost_group_id', :'nullEntryGroupID'::uuid,
                'event_id', :'nullEntryEventID'::uuid,
                'invitation_id', ec.invitation_id
            )),
            'removed', '[]'::jsonb,
            'revision', 1
        )
        from event_cohost ec
        where ec.event_id = :'nullEntryEventID'::uuid
        and ec.group_id = :'nullEntryGroupID'::uuid
    ),
    'Should ignore null co-host entries'
);

-- Keep the inactive co-host and add a valid one
select sync_event_cohosts(
    :'actorUserID'::uuid,
    :'groupID'::uuid,
    :'inactiveExistingEventID'::uuid,
    array[:'inactiveExistingGroupID'::uuid, :'keepAddedGroupID'::uuid],
    0
) as "inactiveExistingResult" \gset

-- Should keep an existing inactive co-host while adding another valid co-host
select is(
    :'inactiveExistingResult'::jsonb,
    (
        select jsonb_build_object(
            'added', jsonb_build_array(jsonb_build_object(
                'cohost_group_id', :'keepAddedGroupID'::uuid,
                'event_id', :'inactiveExistingEventID'::uuid,
                'invitation_id', ec.invitation_id
            )),
            'removed', '[]'::jsonb,
            'revision', 1
        )
        from event_cohost ec
        where ec.event_id = :'inactiveExistingEventID'::uuid
        and ec.group_id = :'keepAddedGroupID'::uuid
    ),
    'Should keep an existing inactive co-host while adding another valid co-host'
);

-- Re-open the canceled, rejected and removed invitations
select sync_event_cohosts(
    :'actorUserID'::uuid,
    :'groupID'::uuid,
    :'reinviteEventID'::uuid,
    array[:'canceledReinviteGroupID'::uuid, :'rejectedReinviteGroupID'::uuid, :'removedReinviteGroupID'::uuid],
    0
) as "reinviteResult" \gset

-- Should re-invite rejected, canceled and removed rows with fresh invitations
select is(
    :'reinviteResult'::jsonb,
    (
        select jsonb_build_object(
            'added', jsonb_agg(jsonb_build_object(
                'cohost_group_id', ec.group_id,
                'event_id', ec.event_id,
                'invitation_id', ec.invitation_id
            ) order by ec.group_id),
            'removed', '[]'::jsonb,
            'revision', 1
        )
        from event_cohost ec
        where ec.event_id = :'reinviteEventID'::uuid
    ),
    'Should re-invite rejected, canceled and removed rows with fresh invitations'
);

-- Should clear approval and response evidence when re-inviting
select results_eq(
    format(
        $$
            select
                group_id,
                event_cohost_status_id,
                invitation_id = any(array[%L::uuid, %L::uuid, %L::uuid]) as reused_invitation,
                invited_at,
                approved_at,
                invited_by,
                responded_at,
                responded_by
            from event_cohost
            where event_id = %L::uuid
            order by group_id
        $$,
        :'canceledReinviteInvitationID',
        :'rejectedReinviteInvitationID',
        :'removedReinviteInvitationID',
        :'reinviteEventID'
    ),
    format(
        $$
            values
                (%1$L::uuid, 'pending', false, current_timestamp, null::timestamptz, %4$L::uuid, null::timestamptz, null::uuid),
                (%2$L::uuid, 'pending', false, current_timestamp, null::timestamptz, %4$L::uuid, null::timestamptz, null::uuid),
                (%3$L::uuid, 'pending', false, current_timestamp, null::timestamptz, %4$L::uuid, null::timestamptz, null::uuid)
        $$,
        :'canceledReinviteGroupID',
        :'rejectedReinviteGroupID',
        :'removedReinviteGroupID',
        :'actorUserID'
    ),
    'Should clear approval and response evidence when re-inviting'
);

-- Should reject a co-host group in an inactive community
select throws_ok(
    format(
        'select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[%L::uuid], 0)',
        :'actorUserID', :'groupID', :'validationEventID', :'inactiveCommunityGroupID'
    ),
    'OCG01',
    'co-host group not found or inactive',
    'Should reject a co-host group in an inactive community'
);

-- Should reject a missing co-host group
select throws_ok(
    format(
        'select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[%L::uuid], 0)',
        :'actorUserID', :'groupID', :'validationEventID', :'missingGroupID'
    ),
    'OCG01',
    'co-host group not found or inactive',
    'Should reject a missing co-host group'
);

-- Should reject additions while published
select throws_ok(
    format(
        'select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[%L::uuid, %L::uuid], 0)',
        :'actorUserID', :'groupID', :'publishedEventID', :'publishedExistingGroupID', :'publishedAddGroupID'
    ),
    'OCG01',
    'co-hosts cannot be changed while the event is published',
    'Should reject additions while published'
);

-- Should reject canceled events
select throws_ok(
    format(
        'select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[]::uuid[], 0)',
        :'actorUserID', :'groupID', :'canceledEventID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject canceled events'
);

-- Should reject events owned by another group
select throws_ok(
    format(
        'select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[]::uuid[], 0)',
        :'actorUserID', :'otherGroupID', :'validationEventID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject events owned by another group'
);

-- Should reject inactive groups for new invitations
select throws_ok(
    format(
        'select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[%L::uuid], 0)',
        :'actorUserID', :'groupID', :'validationEventID', :'inactiveNewGroupID'
    ),
    'OCG01',
    'co-host group not found or inactive',
    'Should reject inactive groups for new invitations'
);

-- Should reject more than ten co-hosts
select throws_ok(
    format(
        'select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[%L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid], 0)',
        :'actorUserID', :'groupID', :'validationEventID',
        :'overflowGroup01ID', :'overflowGroup02ID', :'overflowGroup03ID', :'overflowGroup04ID',
        :'overflowGroup05ID', :'overflowGroup06ID', :'overflowGroup07ID', :'overflowGroup08ID',
        :'overflowGroup09ID', :'overflowGroup10ID', :'overflowGroup11ID'
    ),
    'OCG01',
    'too many co-hosts',
    'Should reject more than ten co-hosts'
);

-- Should reject removals while published
select throws_ok(
    format(
        'select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[]::uuid[], 0)',
        :'actorUserID', :'groupID', :'publishedEventID'
    ),
    'OCG01',
    'co-hosts cannot be changed while the event is published',
    'Should reject removals while published'
);

-- Should reject stale revisions
select throws_ok(
    format(
        'select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[]::uuid[], 1)',
        :'actorUserID', :'groupID', :'staleEventID'
    ),
    'OCG01',
    'co-hosts changed since this page was loaded; reload to continue',
    'Should reject stale revisions'
);

-- Should reject the owner group
select throws_ok(
    format(
        'select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[%L::uuid], 0)',
        :'actorUserID', :'groupID', :'validationEventID', :'groupID'
    ),
    'OCG01',
    'event group cannot co-host its own event',
    'Should reject the owner group'
);

-- Should remove omitted active co-hosts
select is(
    sync_event_cohosts(
        :'actorUserID'::uuid,
        :'groupID'::uuid,
        :'removeEventID'::uuid,
        array[]::uuid[],
        0
    )::jsonb,
    jsonb_build_object(
        'added', '[]'::jsonb,
        'removed', jsonb_build_array(jsonb_build_object(
            'cohost_group_id', :'removeGroupID'::uuid,
            'event_id', :'removeEventID'::uuid,
            'invitation_id', :'removeInvitationID'::uuid
        )),
        'revision', 1
    ),
    'Should remove omitted active co-hosts'
);

-- Should persist the removal with the actor response
select results_eq(
    format(
        $$
            select
                e.cohosts_revision,
                ec.event_cohost_status_id,
                ec.updated_at,
                ec.responded_at,
                ec.responded_by
            from event_cohost ec
            join event e using (event_id)
            where ec.event_id = %L::uuid
        $$,
        :'removeEventID'
    ),
    format(
        $$
            values (1, 'removed', current_timestamp, current_timestamp, %L::uuid)
        $$,
        :'actorUserID'
    ),
    'Should persist the removal with the actor response'
);

-- Should audit removals on owner and co-host scopes
select results_eq(
    format(
        $$
            select action, actor_user_id, actor_username, community_id, details, group_id
            from audit_log
            where event_id = %L::uuid
            and action = 'event_cohost_removed'
            order by group_id
        $$,
        :'removeEventID'
    ),
    format(
        $$
            with removal as (
                select jsonb_build_object(
                    'cohost_group_id', %3$L::uuid,
                    'from_status', 'approved',
                    'invitation_id', %5$L::uuid,
                    'owner_group_id', %4$L::uuid,
                    'to_status', 'removed'
                ) as details
            )
            select 'event_cohost_removed', %1$L::uuid, 'sync-cohosts-actor', %2$L::uuid, details, %4$L::uuid from removal
            union all
            select 'event_cohost_removed', %1$L::uuid, 'sync-cohosts-actor', %2$L::uuid, details, %3$L::uuid from removal
        $$,
        :'actorUserID',
        :'communityID',
        :'removeGroupID',
        :'groupID',
        :'removeInvitationID'
    ),
    'Should audit removals on owner and co-host scopes'
);

-- Should treat duplicate and reordered unchanged requests as a no-op
select is(
    sync_event_cohosts(
        :'actorUserID'::uuid,
        :'groupID'::uuid,
        :'unchangedEventID'::uuid,
        array[:'unchangedSecondGroupID'::uuid, :'unchangedFirstGroupID'::uuid, :'unchangedSecondGroupID'::uuid],
        0
    )::jsonb,
    '{"added":[],"removed":[],"revision":0}'::jsonb,
    'Should treat duplicate and reordered unchanged requests as a no-op'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
