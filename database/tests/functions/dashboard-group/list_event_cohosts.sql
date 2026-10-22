-- Tests listing event co-host invitations for the owner editor.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvedGroupID 'e5090000-0000-0000-0000-000000000001'
\set approvedInvitationID 'e5090000-0000-0000-0000-000000000002'
\set communityID 'e5090000-0000-0000-0000-000000000003'
\set deletedEventID 'e5090000-0000-0000-0000-000000000004'
\set eventCategoryID 'e5090000-0000-0000-0000-000000000005'
\set eventID 'e5090000-0000-0000-0000-000000000006'
\set groupCategoryID 'e5090000-0000-0000-0000-000000000007'
\set groupID 'e5090000-0000-0000-0000-000000000008'
\set inactivePendingGroupID 'e5090000-0000-0000-0000-000000000009'
\set missingEventID 'e5090000-0000-0000-0000-000000000010'
\set otherGroupID 'e5090000-0000-0000-0000-000000000011'
\set pendingInvitationID 'e5090000-0000-0000-0000-000000000012'
\set removedGroupID 'e5090000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community and categories
select fx_community(:'communityID', jsonb_build_object(
    'active', true,
    'display_name', 'Editor Community',
    'logo_url', 'https://example.test/editor-community.png',
    'name', 'editor-community'
));
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');

-- Active approved co-host group with its own logo and pretty slug
select fx_group(:'approvedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'logo_url', 'https://example.test/beta-approved.png',
    'name', 'Beta Approved',
    'slug', 'beta-approved',
    'slug_pretty', 'beta'
));

-- Owner group
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Inactive pending co-host group without a logo
select fx_group(:'inactivePendingGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'logo_url', null,
    'name', 'Alpha Pending',
    'slug', 'alpha-pending'
));

-- Group that owns no listed event
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Removed co-host group hidden from the listing
select fx_group(:'removedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Removed Hidden'));

-- Deleted event with a pending co-host row
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'cohosts_revision', 3,
    'deleted', true
));

-- Event with current and removed co-host rows
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('cohosts_revision', 6));

-- Co-host rows across statuses
insert into event_cohost (
    approved_at,
    event_cohost_status_id,
    event_id,
    group_id,
    invitation_id,
    invited_at
) values
    (
        '2025-01-02 00:00:00+00',
        'approved',
        :'eventID',
        :'approvedGroupID',
        :'approvedInvitationID',
        '2025-01-01 00:00:00+00'
    ),
    (
        null,
        'pending',
        :'eventID',
        :'inactivePendingGroupID',
        :'pendingInvitationID',
        '2025-01-03 00:00:00+00'
    ),
    (
        '2025-01-02 00:00:00+00',
        'removed',
        :'eventID',
        :'removedGroupID',
        gen_random_uuid(),
        '2025-01-01 00:00:00+00'
    ),
    (
        null,
        'pending',
        :'deletedEventID',
        :'approvedGroupID',
        gen_random_uuid(),
        '2025-01-01 00:00:00+00'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return an empty result for deleted events
select is(
    list_event_cohosts(:'groupID'::uuid, :'deletedEventID'::uuid)::jsonb,
    '{"cohosts":[],"revision":0}'::jsonb,
    'Should return an empty result for deleted events'
);

-- Should return an empty result for events of another group
select is(
    list_event_cohosts(:'otherGroupID'::uuid, :'eventID'::uuid)::jsonb,
    '{"cohosts":[],"revision":0}'::jsonb,
    'Should return an empty result for events of another group'
);

-- Should return an empty result for missing events
select is(
    list_event_cohosts(:'groupID'::uuid, :'missingEventID'::uuid)::jsonb,
    '{"cohosts":[],"revision":0}'::jsonb,
    'Should return an empty result for missing events'
);

-- Should return pending and approved co-hosts ordered by name with the revision
select is(
    list_event_cohosts(:'groupID'::uuid, :'eventID'::uuid)::jsonb,
    jsonb_build_object(
        'cohosts', jsonb_build_array(
            jsonb_build_object(
                'community_display_name', 'Editor Community',
                'community_name', 'editor-community',
                'group_active', false,
                'group_id', :'inactivePendingGroupID'::uuid,
                'invitation_id', :'pendingInvitationID'::uuid,
                'invited_at', 1735862400,
                'logo_url', 'https://example.test/editor-community.png',
                'name', 'Alpha Pending',
                'slug', 'alpha-pending',
                'status', 'pending'
            ),
            jsonb_build_object(
                'community_display_name', 'Editor Community',
                'community_name', 'editor-community',
                'group_active', true,
                'group_id', :'approvedGroupID'::uuid,
                'invitation_id', :'approvedInvitationID'::uuid,
                'invited_at', 1735689600,
                'logo_url', 'https://example.test/beta-approved.png',
                'name', 'Beta Approved',
                'slug', 'beta-approved',
                'status', 'approved',

                'slug_pretty', 'beta'
            )
        ),
        'revision', 6
    ),
    'Should return pending and approved co-hosts ordered by name with the revision'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
