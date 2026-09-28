-- Tests listing co-hosted events for a group dashboard.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e50a0000-0000-0000-0000-000000000001'
\set communityID 'e50a0000-0000-0000-0000-000000000002'
\set eventCategoryID 'e50a0000-0000-0000-0000-000000000003'
\set eventID 'e50a0000-0000-0000-0000-000000000004'
\set groupCategoryID 'e50a0000-0000-0000-0000-000000000005'
\set invitationID 'e50a0000-0000-0000-0000-000000000006'
\set ownerGroupID 'e50a0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and event
select fx_community(:'communityID', jsonb_build_object('display_name', 'Hosted Community', 'name', 'hosted-community'));
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'ownerGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Owner Group', 'slug', 'owner-group'));
select fx_event(:'eventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', '2025-01-01 10:00:00+00'
));

-- Approved co-host event row
insert into event_cohost (
    approved_at,
    event_cohost_status_id,
    event_id,
    group_id,
    invitation_id,
    invited_at
) values (
    '2024-12-01 00:00:00+00',
    'approved',
    :'eventID',
    :'cohostGroupID',
    :'invitationID',
    '2024-11-01 00:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return co-hosted events and total
select is(
    list_group_cohosted_events(:'cohostGroupID'::uuid, '{}'::jsonb)::jsonb @> format(
        '{"total":1,"events":[{"event_id":"%s","invitation_id":"%s","status":"approved"}]}',
        :'eventID',
        :'invitationID'
    )::jsonb,
    true,
    'Should return co-hosted events and total'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
