-- Tests approving event co-host invitations.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e50d0000-0000-0000-0000-000000000001'
\set communityID 'e50d0000-0000-0000-0000-000000000002'
\set eventCategoryID 'e50d0000-0000-0000-0000-000000000003'
\set eventID 'e50d0000-0000-0000-0000-000000000004'
\set groupCategoryID 'e50d0000-0000-0000-0000-000000000005'
\set groupID 'e50d0000-0000-0000-0000-000000000006'
\set invitationID 'e50d0000-0000-0000-0000-000000000007'
\set userID 'e50d0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups, event and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');
select fx_user(:'userID');

-- Pending co-host invitation
insert into event_cohost (
    event_id,
    group_id,
    invitation_id
) values (
    :'eventID',
    :'cohostGroupID',
    :'invitationID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should approve a pending invitation
select is(
    approve_event_cohost(:'userID'::uuid, :'cohostGroupID'::uuid, :'invitationID'::uuid)::jsonb @> format(
        '{"cohost_group_id":"%s","event_id":"%s","invitation_id":"%s","owner_group_id":"%s"}',
        :'cohostGroupID',
        :'eventID',
        :'invitationID',
        :'groupID'
    )::jsonb,
    true,
    'Should approve a pending invitation'
);

select is(
    (select event_cohost_status_id from event_cohost where event_id = :'eventID'),
    'approved',
    'Should approve a pending invitation'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
