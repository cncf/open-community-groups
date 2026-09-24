-- Tests public event co-host JSON projection.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvedGroupID 'e5010000-0000-0000-0000-000000000001'
\set communityID 'e5010000-0000-0000-0000-000000000002'
\set eventCategoryID 'e5010000-0000-0000-0000-000000000003'
\set eventID 'e5010000-0000-0000-0000-000000000004'
\set groupCategoryID 'e5010000-0000-0000-0000-000000000005'
\set groupID 'e5010000-0000-0000-0000-000000000006'
\set pendingGroupID 'e5010000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and event
select fx_community(:'communityID', jsonb_build_object(
    'display_name', 'Public Community',
    'logo_url', 'https://example.test/public-community.png',
    'name', 'public-community'
));
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'approvedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'logo_url', null,
    'name', 'Approved Co-host',
    'slug', 'approved-cohost',
    'slug_pretty', 'approved'
));
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'pendingGroupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Approved co-host shown publicly
insert into event_cohost (
    approved_at,
    event_cohost_status_id,
    event_id,
    group_id
) values (
    '2025-01-01 00:00:00+00',
    'approved',
    :'eventID',
    :'approvedGroupID'
);

-- Pending co-host hidden publicly
insert into event_cohost (event_id, group_id)
values (:'eventID', :'pendingGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return only publicly credited co-hosts
select is(
    event_cohosts_json(:'eventID'::uuid),
    format('[{
        "community_display_name": "Public Community",
        "community_name": "public-community",
        "group_id": "%s",
        "logo_url": "https://example.test/public-community.png",
        "name": "Approved Co-host",
        "slug": "approved-cohost",
        "slug_pretty": "approved"
    }]', :'approvedGroupID')::jsonb,
    'Should return only publicly credited co-hosts'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
