-- Tests cancel_event_cohost success, published allowance, stale invitation, and rejection branches.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvedEventID 'e51d0000-0000-0000-0000-000000000001'
\set cohostGroupID 'e51d0000-0000-0000-0000-000000000002'
\set communityID 'e51d0000-0000-0000-0000-000000000003'
\set eventCategoryID 'e51d0000-0000-0000-0000-000000000004'
\set groupCategoryID 'e51d0000-0000-0000-0000-000000000005'
\set groupID 'e51d0000-0000-0000-0000-000000000006'
\set invitationID 'e51d0000-0000-0000-0000-000000000007'
\set pendingEventID 'e51d0000-0000-0000-0000-000000000008'
\set userID 'e51d0000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups, events and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'approvedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'pendingEventID', :'groupID', :'eventCategoryID');
select fx_user(:'userID');

-- Approved and pending invitations covering cancellation outcomes
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id, invitation_id)
values ('2025-01-01 00:00:00+00', 'approved', :'approvedEventID', :'cohostGroupID', :'invitationID');
insert into event_cohost (event_id, group_id)
values (:'pendingEventID', :'cohostGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel approved co-hosting on a published event
select ok(
    cancel_event_cohost(:'userID'::uuid, :'cohostGroupID'::uuid, :'invitationID'::uuid)::jsonb
        @> format('{"cohost_group_id":"%s","event_id":"%s","owner_group_id":"%s"}', :'cohostGroupID', :'approvedEventID', :'groupID')::jsonb,
    'Should cancel approved co-hosting on a published event'
);

-- Should keep approval evidence and advance revision
select results_eq(
    format($$select event_cohost_status_id, approved_at is not null, cohosts_revision from event_cohost join event using (event_id) where event_id = %L::uuid$$, :'approvedEventID'),
    $$ values ('canceled', true, 1) $$,
    'Should keep approval evidence and advance revision'
);

-- Should audit cancellation on owner and co-host scopes
select is((select count(*)::int from audit_log where event_id = :'approvedEventID' and action = 'event_cohost_canceled'), 2, 'Should audit cancellation on owner and co-host scopes');

-- Should reject missing invitations
select throws_ok(
    format('select cancel_event_cohost(%L::uuid, %L::uuid, gen_random_uuid())', :'userID', :'cohostGroupID'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject missing invitations'
);

-- Should reject invitations that are not approved
select throws_ok(
    format('select cancel_event_cohost(%L::uuid, %L::uuid, invitation_id) from event_cohost where event_id = %L::uuid', :'userID', :'cohostGroupID', :'pendingEventID'),
    'OCG01',
    'co-hosting is not approved',
    'Should reject invitations that are not approved'
);

-- Should reject replay after cancellation
select throws_ok(
    format('select cancel_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'userID', :'cohostGroupID', :'invitationID'),
    'OCG01',
    'co-hosting is not approved',
    'Should reject replay after cancellation'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
