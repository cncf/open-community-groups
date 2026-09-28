-- Tests sync_event_cohosts validation, state transitions, revision, audit, and inactive existing behavior.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(19);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set addEventID 'e5150000-0000-0000-0000-000000000001'
\set addGroupID 'e5150000-0000-0000-0000-000000000002'
\set canceledEventID 'e5150000-0000-0000-0000-000000000003'
\set canceledReinviteGroupID 'e5150000-0000-0000-0000-000000000004'
\set communityID 'e5150000-0000-0000-0000-000000000005'
\set deletedEventID 'e5150000-0000-0000-0000-000000000006'
\set eventCategoryID 'e5150000-0000-0000-0000-000000000007'
\set groupCategoryID 'e5150000-0000-0000-0000-000000000008'
\set groupID 'e5150000-0000-0000-0000-000000000009'
\set inactiveExistingEventID 'e5150000-0000-0000-0000-00000000000a'
\set inactiveExistingGroupID 'e5150000-0000-0000-0000-00000000000b'
\set inactiveNewGroupID 'e5150000-0000-0000-0000-00000000000c'
\set invalidMixedEventID 'e5150000-0000-0000-0000-00000000000d'
\set invalidMixedValidGroupID 'e5150000-0000-0000-0000-00000000000e'
\set keepAddedGroupID 'e5150000-0000-0000-0000-00000000000f'
\set overflowEventID 'e5150000-0000-0000-0000-000000000010'
\set overflowGroup01ID 'e5150000-0000-0000-0000-000000000011'
\set overflowGroup02ID 'e5150000-0000-0000-0000-000000000012'
\set overflowGroup03ID 'e5150000-0000-0000-0000-000000000013'
\set overflowGroup04ID 'e5150000-0000-0000-0000-000000000014'
\set overflowGroup05ID 'e5150000-0000-0000-0000-000000000015'
\set overflowGroup06ID 'e5150000-0000-0000-0000-000000000016'
\set overflowGroup07ID 'e5150000-0000-0000-0000-000000000017'
\set overflowGroup08ID 'e5150000-0000-0000-0000-000000000018'
\set overflowGroup09ID 'e5150000-0000-0000-0000-000000000019'
\set overflowGroup10ID 'e5150000-0000-0000-0000-00000000001a'
\set overflowGroup11ID 'e5150000-0000-0000-0000-00000000001b'
\set publishedAddGroupID 'e5150000-0000-0000-0000-00000000001c'
\set publishedEventID 'e5150000-0000-0000-0000-00000000001d'
\set publishedExistingGroupID 'e5150000-0000-0000-0000-00000000001e'
\set rejectedReinviteGroupID 'e5150000-0000-0000-0000-00000000001f'
\set reinviteEventID 'e5150000-0000-0000-0000-000000000020'
\set removeEventID 'e5150000-0000-0000-0000-000000000021'
\set removeGroupID 'e5150000-0000-0000-0000-000000000022'
\set removedReinviteGroupID 'e5150000-0000-0000-0000-000000000023'
\set staleEventID 'e5150000-0000-0000-0000-000000000024'
\set userID 'e5150000-0000-0000-0000-000000000025'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, owner group, actor and events
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_user(:'userID', jsonb_build_object('username', 'sync-cohosts-actor'));
select fx_event(:'addEventID', :'groupID', :'eventCategoryID');
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object('canceled', true));
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('deleted', true));
select fx_event(:'inactiveExistingEventID', :'groupID', :'eventCategoryID');
select fx_event(:'invalidMixedEventID', :'groupID', :'eventCategoryID');
select fx_event(:'overflowEventID', :'groupID', :'eventCategoryID');
select fx_event(:'publishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'reinviteEventID', :'groupID', :'eventCategoryID');
select fx_event(:'removeEventID', :'groupID', :'eventCategoryID');
select fx_event(:'staleEventID', :'groupID', :'eventCategoryID', jsonb_build_object('cohosts_revision', 2));

-- Requested co-host groups
select fx_group(:'addGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'canceledReinviteGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'inactiveExistingGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));
select fx_group(:'inactiveNewGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));
select fx_group(:'invalidMixedValidGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'keepAddedGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'publishedAddGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'publishedExistingGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'rejectedReinviteGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'removeGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'removedReinviteGroupID', :'communityID', :'groupCategoryID');
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

-- Existing co-host rows for removal, publication, re-invitation and inactive keep scenarios
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id, invitation_id, responded_at, responded_by) values
    ('2025-01-01 00:00:00+00', 'approved', :'inactiveExistingEventID', :'inactiveExistingGroupID', gen_random_uuid(), '2025-01-01 00:00:00+00', :'userID'),
    ('2025-01-01 00:00:00+00', 'canceled', :'reinviteEventID', :'canceledReinviteGroupID', gen_random_uuid(), '2025-01-01 00:00:00+00', :'userID'),
    (null, 'rejected', :'reinviteEventID', :'rejectedReinviteGroupID', gen_random_uuid(), '2025-01-01 00:00:00+00', :'userID'),
    ('2025-01-01 00:00:00+00', 'removed', :'reinviteEventID', :'removedReinviteGroupID', gen_random_uuid(), '2025-01-01 00:00:00+00', :'userID'),
    ('2025-01-01 00:00:00+00', 'approved', :'publishedEventID', :'publishedExistingGroupID', gen_random_uuid(), '2025-01-01 00:00:00+00', :'userID'),
    ('2025-01-01 00:00:00+00', 'approved', :'removeEventID', :'removeGroupID', gen_random_uuid(), '2025-01-01 00:00:00+00', :'userID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should add a co-host and return the full reference shape
select ok(
    sync_event_cohosts(:'userID'::uuid, :'groupID'::uuid, :'addEventID'::uuid, array[:'addGroupID'::uuid], 0)::jsonb
        @> format('{"added":[{"cohost_group_id":"%s","event_id":"%s"}],"removed":[],"revision":1}', :'addGroupID', :'addEventID')::jsonb,
    'Should add a co-host and return the full reference shape'
);

-- Should persist the added row as pending
select is((select event_cohost_status_id from event_cohost where event_id = :'addEventID'), 'pending', 'Should persist the added row as pending');

-- Should audit invitations on owner and co-host scopes
select is((select count(*)::int from audit_log where event_id = :'addEventID' and action = 'event_cohost_invited'), 2, 'Should audit invitations on owner and co-host scopes');

-- Should treat duplicate and reordered unchanged requests as a no-op
select is(
    sync_event_cohosts(:'userID'::uuid, :'groupID'::uuid, :'addEventID'::uuid, array[:'addGroupID'::uuid, :'addGroupID'::uuid], 1)::jsonb,
    '{"added":[],"removed":[],"revision":1}'::jsonb,
    'Should treat duplicate and reordered unchanged requests as a no-op'
);

-- Should remove omitted active co-hosts
select ok(
    sync_event_cohosts(:'userID'::uuid, :'groupID'::uuid, :'removeEventID'::uuid, array[]::uuid[], 0)::jsonb
        @> format('{"removed":[{"cohost_group_id":"%s","event_id":"%s"}],"revision":1}', :'removeGroupID', :'removeEventID')::jsonb,
    'Should remove omitted active co-hosts'
);

-- Should re-invite rejected, canceled and removed rows with cleared response evidence
select lives_ok(
    format(
        'select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[%L::uuid,%L::uuid,%L::uuid], 0)',
        :'userID', :'groupID', :'reinviteEventID',
        :'canceledReinviteGroupID', :'rejectedReinviteGroupID', :'removedReinviteGroupID'
    ),
    'Should re-invite rejected, canceled and removed rows with cleared response evidence'
);

-- Should clear approval and response evidence when re-inviting
select results_eq(
    format($$
        select event_cohost_status_id, approved_at, responded_at, responded_by
        from event_cohost
        where event_id = %L::uuid
        order by group_id
    $$, :'reinviteEventID'),
    $$ values
        ('pending', null::timestamptz, null::timestamptz, null::uuid),
        ('pending', null::timestamptz, null::timestamptz, null::uuid),
        ('pending', null::timestamptz, null::timestamptz, null::uuid)
    $$,
    'Should clear approval and response evidence when re-inviting'
);

-- Should reject stale revisions
select throws_ok(
    format('select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[]::uuid[], 1)', :'userID', :'groupID', :'staleEventID'),
    'OCG01',
    'co-hosts changed since this page was loaded; reload to continue',
    'Should reject stale revisions'
);

-- Should reject additions while published
select throws_ok(
    format('select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[%L::uuid,%L::uuid], 0)', :'userID', :'groupID', :'publishedEventID', :'publishedExistingGroupID', :'publishedAddGroupID'),
    'OCG01',
    'co-hosts cannot be changed while the event is published',
    'Should reject additions while published'
);

-- Should reject removals while published
select throws_ok(
    format('select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[]::uuid[], 0)', :'userID', :'groupID', :'publishedEventID'),
    'OCG01',
    'co-hosts cannot be changed while the event is published',
    'Should reject removals while published'
);

-- Should allow unchanged published co-host selections
select is(
    sync_event_cohosts(:'userID'::uuid, :'groupID'::uuid, :'publishedEventID'::uuid, array[:'publishedExistingGroupID'::uuid], 0)::jsonb,
    '{"added":[],"removed":[],"revision":0}'::jsonb,
    'Should allow unchanged published co-host selections'
);

-- Should reject canceled or deleted events
select throws_ok(
    format('select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[]::uuid[], 0)', :'userID', :'groupID', :'canceledEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject canceled events'
);
select throws_ok(
    format('select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[]::uuid[], 0)', :'userID', :'groupID', :'deletedEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject deleted events'
);

-- Should reject the owner group
select throws_ok(
    format('select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[%L::uuid], 0)', :'userID', :'groupID', :'overflowEventID', :'groupID'),
    'OCG01',
    'event group cannot co-host its own event',
    'Should reject the owner group'
);

-- Should reject inactive groups for new invitations
select throws_ok(
    format('select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[%L::uuid], 0)', :'userID', :'groupID', :'overflowEventID', :'inactiveNewGroupID'),
    'OCG01',
    'co-host group not found or inactive',
    'Should reject inactive groups for new invitations'
);

-- Should reject more than ten co-hosts
select throws_ok(
    format(
        'select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid], 0)',
        :'userID', :'groupID', :'overflowEventID',
        :'overflowGroup01ID', :'overflowGroup02ID', :'overflowGroup03ID', :'overflowGroup04ID', :'overflowGroup05ID', :'overflowGroup06ID',
        :'overflowGroup07ID', :'overflowGroup08ID', :'overflowGroup09ID', :'overflowGroup10ID', :'overflowGroup11ID'
    ),
    'OCG01',
    'too many co-hosts',
    'Should reject more than ten co-hosts'
);

-- Should apply nothing when a mixed request includes an invalid group
select throws_ok(
    format('select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[%L::uuid,%L::uuid], 0)', :'userID', :'groupID', :'invalidMixedEventID', :'invalidMixedValidGroupID', :'inactiveNewGroupID'),
    'OCG01',
    'co-host group not found or inactive',
    'Should apply nothing when a mixed request includes an invalid group'
);
select is((select count(*)::int from event_cohost where event_id = :'invalidMixedEventID'), 0, 'Should apply nothing when a mixed request includes an invalid group');

-- Should keep an existing inactive co-host while adding another valid co-host
select ok(
    sync_event_cohosts(:'userID'::uuid, :'groupID'::uuid, :'inactiveExistingEventID'::uuid, array[:'inactiveExistingGroupID'::uuid, :'keepAddedGroupID'::uuid], 0)::jsonb
        @> format('{"added":[{"cohost_group_id":"%s","event_id":"%s"}],"removed":[],"revision":1}', :'keepAddedGroupID', :'inactiveExistingEventID')::jsonb,
    'Should keep an existing inactive co-host while adding another valid co-host'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
