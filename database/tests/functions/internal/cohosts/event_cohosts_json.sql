-- Tests public event co-host JSON projection.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvedGroupID 'e5010000-0000-0000-0000-000000000001'
\set canceledGroupID 'e5010000-0000-0000-0000-000000000002'
\set communityID 'e5010000-0000-0000-0000-000000000003'
\set emptyEventID 'e5010000-0000-0000-0000-000000000004'
\set eventCanceledApprovedGroupID 'e5010000-0000-0000-0000-000000000005'
\set eventCanceledNoApprovalGroupID 'e5010000-0000-0000-0000-000000000006'
\set eventCategoryID 'e5010000-0000-0000-0000-000000000007'
\set eventDeletedGroupID 'e5010000-0000-0000-0000-000000000008'
\set eventID 'e5010000-0000-0000-0000-000000000009'
\set groupCategoryID 'e5010000-0000-0000-0000-00000000000a'
\set groupID 'e5010000-0000-0000-0000-00000000000b'
\set inactiveCommunityCategoryID 'e5010000-0000-0000-0000-00000000000c'
\set inactiveCommunityGroupID 'e5010000-0000-0000-0000-00000000000d'
\set inactiveCommunityID 'e5010000-0000-0000-0000-00000000000e'
\set inactiveGroupID 'e5010000-0000-0000-0000-00000000000f'
\set pendingGroupID 'e5010000-0000-0000-0000-000000000010'
\set rejectedGroupID 'e5010000-0000-0000-0000-000000000011'
\set removedGroupID 'e5010000-0000-0000-0000-000000000012'
\set zuluApprovedGroupID 'e5010000-0000-0000-0000-000000000013'
\set zuluTwinGroupID 'e5010000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities and categories
select fx_community(:'communityID', jsonb_build_object(
    'display_name', 'Matrix Community',
    'logo_url', 'https://example.test/matrix-community.png',
    'name', 'matrix-community'
));
select fx_community(:'inactiveCommunityID', jsonb_build_object(
    'active', false,
    'display_name', 'Inactive Matrix Community',
    'name', 'inactive-matrix-community'
));
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group_category(:'inactiveCommunityCategoryID', :'inactiveCommunityID');

-- Owner group and events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'emptyEventID', :'groupID', :'eventCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Visible co-host groups (no logo falls back to the community logo)
select fx_group(:'approvedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'logo_url', null,
    'name', 'Alpha Approved',
    'slug', 'alpha-approved'
));
select fx_group(:'eventCanceledApprovedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'logo_url', null,
    'name', 'Beta Event Canceled',
    'slug', 'beta-event-canceled'
));
select fx_group(:'zuluApprovedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'logo_url', 'https://example.test/zulu.png',
    'name', 'Zulu Approved',
    'slug', 'zulu-approved',
    'slug_pretty', 'zulu'
));

-- Visible co-host group sharing a name, ordered after its twin by group id
select fx_group(:'zuluTwinGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'logo_url', null,
    'name', 'Zulu Approved',
    'slug', 'zulu-twin'
));

-- Hidden co-host groups covering every non-public status and visibility state
select fx_group(:'canceledGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Canceled Hidden', 'slug', 'canceled-hidden'));
select fx_group(:'eventCanceledNoApprovalGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'No Approval Hidden', 'slug', 'no-approval-hidden'));
select fx_group(:'eventDeletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Event Deleted Hidden', 'slug', 'event-deleted-hidden'));
select fx_group(:'inactiveCommunityGroupID', :'inactiveCommunityID', :'inactiveCommunityCategoryID', jsonb_build_object('name', 'Inactive Community Hidden', 'slug', 'inactive-community-hidden'));
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false, 'name', 'Inactive Hidden', 'slug', 'inactive-hidden'));
select fx_group(:'pendingGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Pending Hidden', 'slug', 'pending-hidden'));
select fx_group(:'rejectedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Rejected Hidden', 'slug', 'rejected-hidden'));
select fx_group(:'removedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Removed Hidden', 'slug', 'removed-hidden'));

-- Co-host rows for every status and visibility state (twin inserted first)
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    ('2025-01-01 00:00:00+00', 'approved', :'eventID', :'zuluTwinGroupID'),
    ('2025-01-01 00:00:00+00', 'approved', :'eventID', :'approvedGroupID'),
    ('2025-01-01 00:00:00+00', 'canceled', :'eventID', :'canceledGroupID'),
    ('2025-01-01 00:00:00+00', 'event-canceled', :'eventID', :'eventCanceledApprovedGroupID'),
    (null, 'event-canceled', :'eventID', :'eventCanceledNoApprovalGroupID'),
    ('2025-01-01 00:00:00+00', 'event-deleted', :'eventID', :'eventDeletedGroupID'),
    ('2025-01-01 00:00:00+00', 'approved', :'eventID', :'inactiveCommunityGroupID'),
    ('2025-01-01 00:00:00+00', 'approved', :'eventID', :'inactiveGroupID'),
    (null, 'pending', :'eventID', :'pendingGroupID'),
    (null, 'rejected', :'eventID', :'rejectedGroupID'),
    ('2025-01-01 00:00:00+00', 'removed', :'eventID', :'removedGroupID'),
    ('2025-01-01 00:00:00+00', 'approved', :'eventID', :'zuluApprovedGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return an empty array for events without public co-hosts
select is(
    event_cohosts_json(:'emptyEventID'::uuid),
    '[]'::jsonb,
    'Should return an empty array for events without public co-hosts'
);

-- Should return only public co-hosts ordered by name then group id
-- (a deleted group is never active, so the inactive group covers deleted ones)
select is(
    event_cohosts_json(:'eventID'::uuid),
    format('[
        {
            "community_display_name": "Matrix Community",
            "community_name": "matrix-community",
            "group_id": "%s",
            "logo_url": "https://example.test/matrix-community.png",
            "name": "Alpha Approved",
            "slug": "alpha-approved"
        },
        {
            "community_display_name": "Matrix Community",
            "community_name": "matrix-community",
            "group_id": "%s",
            "logo_url": "https://example.test/matrix-community.png",
            "name": "Beta Event Canceled",
            "slug": "beta-event-canceled"
        },
        {
            "community_display_name": "Matrix Community",
            "community_name": "matrix-community",
            "group_id": "%s",
            "logo_url": "https://example.test/zulu.png",
            "name": "Zulu Approved",
            "slug": "zulu-approved",
            "slug_pretty": "zulu"
        },
        {
            "community_display_name": "Matrix Community",
            "community_name": "matrix-community",
            "group_id": "%s",
            "logo_url": "https://example.test/matrix-community.png",
            "name": "Zulu Approved",
            "slug": "zulu-twin"
        }
    ]', :'approvedGroupID', :'eventCanceledApprovedGroupID', :'zuluApprovedGroupID', :'zuluTwinGroupID')::jsonb,
    'Should return only public co-hosts ordered by name then group id'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
