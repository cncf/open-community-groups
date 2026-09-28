-- Tests event_cohosts_json status, visibility, ordering, and empty cases.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvedGroupID 'e5110000-0000-0000-0000-000000000001'
\set canceledGroupID 'e5110000-0000-0000-0000-000000000002'
\set communityID 'e5110000-0000-0000-0000-000000000003'
\set deletedGroupID 'e5110000-0000-0000-0000-000000000004'
\set emptyEventID 'e5110000-0000-0000-0000-000000000005'
\set eventCanceledApprovedGroupID 'e5110000-0000-0000-0000-000000000006'
\set eventCanceledNoApprovalGroupID 'e5110000-0000-0000-0000-000000000007'
\set eventCategoryID 'e5110000-0000-0000-0000-000000000008'
\set eventDeletedGroupID 'e5110000-0000-0000-0000-000000000009'
\set eventID 'e5110000-0000-0000-0000-00000000000a'
\set groupCategoryID 'e5110000-0000-0000-0000-00000000000b'
\set groupID 'e5110000-0000-0000-0000-00000000000c'
\set inactiveCommunityGroupID 'e5110000-0000-0000-0000-00000000000d'
\set inactiveCommunityID 'e5110000-0000-0000-0000-00000000000e'
\set inactiveCommunityCategoryID 'e5110000-0000-0000-0000-00000000000f'
\set inactiveGroupID 'e5110000-0000-0000-0000-000000000010'
\set pendingGroupID 'e5110000-0000-0000-0000-000000000011'
\set rejectedGroupID 'e5110000-0000-0000-0000-000000000012'
\set removedGroupID 'e5110000-0000-0000-0000-000000000013'
\set zApprovedGroupID 'e5110000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities and categories
select fx_community(:'communityID', jsonb_build_object('display_name', 'Matrix Community', 'logo_url', 'https://example.test/matrix-community.png', 'name', 'matrix-community'));
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false, 'display_name', 'Inactive Matrix Community', 'name', 'inactive-matrix-community'));
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group_category(:'inactiveCommunityCategoryID', :'inactiveCommunityID');

-- Owner events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'emptyEventID', :'groupID', :'eventCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Co-host groups covering every status and visibility state
select fx_group(:'approvedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('logo_url', null, 'name', 'Alpha Approved', 'slug', 'alpha-approved'));
select fx_group(:'canceledGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Canceled Hidden', 'slug', 'canceled-hidden'));
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('deleted', true, 'active', false, 'name', 'Deleted Hidden', 'slug', 'deleted-hidden'));
select fx_group(:'eventCanceledApprovedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Beta Event Canceled', 'slug', 'beta-event-canceled'));
select fx_group(:'eventCanceledNoApprovalGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'No Approval Hidden', 'slug', 'no-approval-hidden'));
select fx_group(:'eventDeletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Event Deleted Hidden', 'slug', 'event-deleted-hidden'));
select fx_group(:'inactiveCommunityGroupID', :'inactiveCommunityID', :'inactiveCommunityCategoryID', jsonb_build_object('name', 'Inactive Community Hidden', 'slug', 'inactive-community-hidden'));
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false, 'name', 'Inactive Hidden', 'slug', 'inactive-hidden'));
select fx_group(:'pendingGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Pending Hidden', 'slug', 'pending-hidden'));
select fx_group(:'rejectedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Rejected Hidden', 'slug', 'rejected-hidden'));
select fx_group(:'removedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Removed Hidden', 'slug', 'removed-hidden'));
select fx_group(:'zApprovedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Zulu Approved', 'slug', 'zulu-approved', 'slug_pretty', 'zulu'));

-- Co-host rows for public projection scenarios
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
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
    ('2025-01-01 00:00:00+00', 'approved', :'eventID', :'deletedGroupID'),
    ('2025-01-01 00:00:00+00', 'approved', :'eventID', :'zApprovedGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return an empty array for events without public co-hosts
select is(
    event_cohosts_json(:'emptyEventID'::uuid),
    '[]'::jsonb,
    'Should return an empty array for events without public co-hosts'
);

-- Should include approved rows
select ok(
    event_cohosts_json(:'eventID'::uuid) @> format('[{"group_id":"%s"}]', :'approvedGroupID')::jsonb,
    'Should include approved rows'
);

-- Should include event-canceled rows with approval evidence
select ok(
    event_cohosts_json(:'eventID'::uuid) @> format('[{"group_id":"%s"}]', :'eventCanceledApprovedGroupID')::jsonb,
    'Should include event-canceled rows with approval evidence'
);

-- Should exclude event-canceled rows without approval evidence
select ok(
    not event_cohosts_json(:'eventID'::uuid) @> format('[{"group_id":"%s"}]', :'eventCanceledNoApprovalGroupID')::jsonb,
    'Should exclude event-canceled rows without approval evidence'
);

-- Should exclude non-public statuses
select is(
    (
        select count(*)::int
        from jsonb_array_elements(event_cohosts_json(:'eventID'::uuid)) item
        where item->>'group_id' in (:'canceledGroupID', :'eventDeletedGroupID', :'pendingGroupID', :'rejectedGroupID', :'removedGroupID')
    ),
    0,
    'Should exclude non-public statuses'
);

-- Should exclude inactive or deleted groups and inactive communities
select is(
    (
        select count(*)::int
        from jsonb_array_elements(event_cohosts_json(:'eventID'::uuid)) item
        where item->>'group_id' in (:'deletedGroupID', :'inactiveCommunityGroupID', :'inactiveGroupID')
    ),
    0,
    'Should exclude inactive or deleted groups and inactive communities'
);

-- Should use the community logo fallback
select is(
    (
        select item->>'logo_url'
        from jsonb_array_elements(event_cohosts_json(:'eventID'::uuid)) item
        where item->>'group_id' = :'approvedGroupID'
    ),
    'https://example.test/matrix-community.png',
    'Should use the community logo fallback'
);

-- Should omit null optional pretty slugs
select ok(
    not (
        select item ? 'slug_pretty'
        from jsonb_array_elements(event_cohosts_json(:'eventID'::uuid)) item
        where item->>'group_id' = :'approvedGroupID'
    ),
    'Should omit null optional pretty slugs'
);

-- Should order visible co-hosts by name then group id
select is(
    (
        select jsonb_agg(item->>'name')
        from jsonb_array_elements(event_cohosts_json(:'eventID'::uuid)) item
    ),
    '["Alpha Approved", "Beta Event Canceled", "Zulu Approved"]'::jsonb,
    'Should order visible co-hosts by name then group id'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
