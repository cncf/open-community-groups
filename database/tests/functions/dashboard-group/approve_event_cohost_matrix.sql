-- Tests approve_event_cohost success, stale invitation, and rejection branches.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID 'e51b0000-0000-0000-0000-000000000001'
\set cohostGroupID 'e51b0000-0000-0000-0000-000000000002'
\set communityID 'e51b0000-0000-0000-0000-000000000003'
\set eventCategoryID 'e51b0000-0000-0000-0000-000000000004'
\set groupCategoryID 'e51b0000-0000-0000-0000-000000000005'
\set groupID 'e51b0000-0000-0000-0000-000000000006'
\set nonPendingEventID 'e51b0000-0000-0000-0000-000000000007'
\set otherGroupID 'e51b0000-0000-0000-0000-000000000008'
\set pendingEventID 'e51b0000-0000-0000-0000-000000000009'
\set publishedEventID 'e51b0000-0000-0000-0000-00000000000a'
\set staleEventID 'e51b0000-0000-0000-0000-00000000000b'
\set staleInvitationID 'e51b0000-0000-0000-0000-00000000000c'
\set successInvitationID 'e51b0000-0000-0000-0000-00000000000d'
\set userID 'e51b0000-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups, events and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object('canceled', true));
select fx_event(:'nonPendingEventID', :'groupID', :'eventCategoryID');
select fx_event(:'pendingEventID', :'groupID', :'eventCategoryID');
select fx_event(:'publishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'staleEventID', :'groupID', :'eventCategoryID');
select fx_user(:'userID');

-- Invitations covering approval outcomes
insert into event_cohost (event_id, group_id, invitation_id) values
    (:'canceledEventID', :'cohostGroupID', gen_random_uuid()),
    (:'pendingEventID', :'cohostGroupID', :'successInvitationID'),
    (:'publishedEventID', :'cohostGroupID', gen_random_uuid()),
    (:'staleEventID', :'cohostGroupID', :'staleInvitationID');
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id)
values ('2025-01-01 00:00:00+00', 'approved', :'nonPendingEventID', :'cohostGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should approve a pending invitation and return notification identifiers
select ok(
    approve_event_cohost(:'userID'::uuid, :'cohostGroupID'::uuid, :'successInvitationID'::uuid)::jsonb
        @> format('{"cohost_group_id":"%s","event_id":"%s","owner_group_id":"%s"}', :'cohostGroupID', :'pendingEventID', :'groupID')::jsonb,
    'Should approve a pending invitation and return notification identifiers'
);

-- Should persist approval and advance revision
select results_eq(
    format($$select event_cohost_status_id, approved_at is not null, cohosts_revision from event_cohost join event using (event_id) where event_id = %L::uuid$$, :'pendingEventID'),
    $$ values ('approved', true, 1) $$,
    'Should persist approval and advance revision'
);

-- Should audit approval on owner and co-host scopes
select is((select count(*)::int from audit_log where event_id = :'pendingEventID' and action = 'event_cohost_approved'), 2, 'Should audit approval on owner and co-host scopes');

-- Should reject missing or stale invitations
select throws_ok(
    format('select approve_event_cohost(%L::uuid, %L::uuid, gen_random_uuid())', :'userID', :'cohostGroupID'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject missing or stale invitations'
);

-- Should reject another group's invitation
select throws_ok(
    format('select approve_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'userID', :'otherGroupID', :'staleInvitationID'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject another group''s invitation'
);

-- Should reject approvals for canceled events
select throws_ok(
    format('select approve_event_cohost(%L::uuid, %L::uuid, invitation_id) from event_cohost where event_id = %L::uuid', :'userID', :'cohostGroupID', :'canceledEventID'),
    'OCG01',
    'event is canceled',
    'Should reject approvals for canceled events'
);

-- Should reject approvals after publication
select throws_ok(
    format('select approve_event_cohost(%L::uuid, %L::uuid, invitation_id) from event_cohost where event_id = %L::uuid', :'userID', :'cohostGroupID', :'publishedEventID'),
    'OCG01',
    'co-hosting can only be approved or rejected before the event is published',
    'Should reject approvals after publication'
);

-- Should reject invitations that are no longer pending
select throws_ok(
    format('select approve_event_cohost(%L::uuid, %L::uuid, invitation_id) from event_cohost where event_id = %L::uuid', :'userID', :'cohostGroupID', :'nonPendingEventID'),
    'OCG01',
    'co-hosting invitation is no longer pending',
    'Should reject invitations that are no longer pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
