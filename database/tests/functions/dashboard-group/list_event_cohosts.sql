-- Tests listing event co-host invitations for the owner editor.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e5090000-0000-0000-0000-000000000001'
\set communityID 'e5090000-0000-0000-0000-000000000002'
\set eventCategoryID 'e5090000-0000-0000-0000-000000000003'
\set eventID 'e5090000-0000-0000-0000-000000000004'
\set groupCategoryID 'e5090000-0000-0000-0000-000000000005'
\set groupID 'e5090000-0000-0000-0000-000000000006'
\set invitationID 'e5090000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and event
select fx_community(:'communityID', jsonb_build_object('display_name', 'Editor Community', 'name', 'editor-community'));
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Editor Co-host', 'slug', 'editor-cohost'));
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('cohosts_revision', 4));

-- Pending editor co-host row
insert into event_cohost (
    event_id,
    group_id,
    invitation_id,
    invited_at
) values (
    :'eventID',
    :'cohostGroupID',
    :'invitationID',
    '2025-01-01 00:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return current co-host rows and revision
select is(
    (list_event_cohosts(:'groupID'::uuid, :'eventID'::uuid)::jsonb #>> '{revision}'),
    '4',
    'Should return current co-host rows and revision'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
