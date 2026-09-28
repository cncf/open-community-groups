-- Tests reject_event_cohost rejects stale invitation ids after re-invites.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e52d0000-0000-0000-0000-000000000001'
\set communityID 'e52d0000-0000-0000-0000-000000000002'
\set eventCategoryID 'e52d0000-0000-0000-0000-000000000003'
\set groupCategoryID 'e52d0000-0000-0000-0000-000000000004'
\set groupID 'e52d0000-0000-0000-0000-000000000005'
\set oldRejectedInvitationID 'e52d0000-0000-0000-0000-000000000006'
\set oldRemovedInvitationID 'e52d0000-0000-0000-0000-000000000007'
\set rejectedEventID 'e52d0000-0000-0000-0000-000000000008'
\set removedEventID 'e52d0000-0000-0000-0000-000000000009'
\set userID 'e52d0000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups, events and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'rejectedEventID', :'groupID', :'eventCategoryID');
select fx_event(:'removedEventID', :'groupID', :'eventCategoryID');
select fx_user(:'userID');

-- Closed invitations that will be re-opened with rotated ids
insert into event_cohost (event_cohost_status_id, event_id, group_id, invitation_id) values
    ('rejected', :'rejectedEventID', :'cohostGroupID', :'oldRejectedInvitationID'),
    ('removed', :'removedEventID', :'cohostGroupID', :'oldRemovedInvitationID');

-- Rotate both invitation ids through the owner sync behavior
select sync_event_cohosts(:'userID'::uuid, :'groupID'::uuid, :'rejectedEventID'::uuid, array[:'cohostGroupID'::uuid], 0);
select sync_event_cohosts(:'userID'::uuid, :'groupID'::uuid, :'removedEventID'::uuid, array[:'cohostGroupID'::uuid], 0);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject rejecting an invitation id rotated after rejection
select throws_ok(
    format('select reject_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'userID', :'cohostGroupID', :'oldRejectedInvitationID'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject rejecting an invitation id rotated after rejection'
);

-- Should reject rejecting an invitation id rotated after removal
select throws_ok(
    format('select reject_event_cohost(%L::uuid, %L::uuid, %L::uuid)', :'userID', :'cohostGroupID', :'oldRemovedInvitationID'),
    'OCG01',
    'co-hosting invitation not found',
    'Should reject rejecting an invitation id rotated after removal'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
