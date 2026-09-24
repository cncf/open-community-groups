-- Tests reject_event_cohost success, stale invitation, and rejection branches.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID 'e51c0000-0000-0000-0000-000000000001'
\set cohostGroupID 'e51c0000-0000-0000-0000-000000000002'
\set communityID 'e51c0000-0000-0000-0000-000000000003'
\set eventCategoryID 'e51c0000-0000-0000-0000-000000000004'
\set groupCategoryID 'e51c0000-0000-0000-0000-000000000005'
\set groupID 'e51c0000-0000-0000-0000-000000000006'
\set nonPendingEventID 'e51c0000-0000-0000-0000-000000000007'
\set pendingEventID 'e51c0000-0000-0000-0000-000000000008'
\set publishedEventID 'e51c0000-0000-0000-0000-000000000009'
\set rejectInvitationID 'e51c0000-0000-0000-0000-00000000000a'
\set userID 'e51c0000-0000-0000-0000-00000000000b'

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
select fx_event(:'nonPendingEventID', :'groupID', :'eventCategoryID');
select fx_event(:'pendingEventID', :'groupID', :'eventCategoryID');
select fx_event(:'publishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_user(:'userID');

-- Invitations covering rejection outcomes
insert into event_cohost (event_id, group_id, invitation_id) values
    (:'canceledEventID', :'cohostGroupID', gen_random_uuid()),
    (:'pendingEventID', :'cohostGroupID', :'rejectInvitationID'),
    (:'publishedEventID', :'cohostGroupID', gen_random_uuid());
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id)
values ('2025-01-01 00:00:00+00', 'approved', :'nonPendingEventID', :'cohostGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a pending invitation and return notification identifiers
select ok(
    reject_event_cohost(:'userID'::uuid, :'cohostGroupID'::uuid, :'rejectInvitationID'::uuid)::jsonb
        @> format('{"cohost_group_id":"%s","event_id":"%s","owner_group_id":"%s"}', :'cohostGroupID', :'pendingEventID', :'groupID')::jsonb,
    'Should reject a pending invitation and return notification identifiers'
);

-- Should persist rejection and advance revision
select results_eq(
    format($$select event_cohost_status_id, cohosts_revision from event_cohost join event using (event_id) where event_id = %L::uuid$$, :'pendingEventID'),
    $$ values ('rejected', 1) $$,
    'Should persist rejection and advance revision'
);

-- Should audit rejection on owner and co-host scopes
select is((select count(*)::int from audit_log where event_id = :'pendingEventID' and action = 'event_cohost_rejected'), 2, 'Should audit rejection on owner and co-host scopes');

-- Should reject missing invitations
select throws_ok(
    format('select reject_event_cohost(%L::uuid, %L::uuid, gen_random_uuid())', :'userID', :'cohostGroupID'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject missing invitations'
);

-- Should reject canceled events
select throws_ok(
    format('select reject_event_cohost(%L::uuid, %L::uuid, invitation_id) from event_cohost where event_id = %L::uuid', :'userID', :'cohostGroupID', :'canceledEventID'),
    'OCG01',
    'event is canceled',
    'Should reject canceled events'
);

-- Should reject after publication
select throws_ok(
    format('select reject_event_cohost(%L::uuid, %L::uuid, invitation_id) from event_cohost where event_id = %L::uuid', :'userID', :'cohostGroupID', :'publishedEventID'),
    'OCG01',
    'co-hosting can only be approved or rejected before the event is published',
    'Should reject after publication'
);

-- Should reject invitations that are no longer pending
select throws_ok(
    format('select reject_event_cohost(%L::uuid, %L::uuid, invitation_id) from event_cohost where event_id = %L::uuid', :'userID', :'cohostGroupID', :'nonPendingEventID'),
    'OCG01',
    'co-hosting invitation is no longer pending',
    'Should reject invitations that are no longer pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
