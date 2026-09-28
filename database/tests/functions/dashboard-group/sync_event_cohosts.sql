-- Tests synchronizing owner-selected event co-hosts.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e50c0000-0000-0000-0000-000000000001'
\set communityID 'e50c0000-0000-0000-0000-000000000002'
\set eventCategoryID 'e50c0000-0000-0000-0000-000000000003'
\set eventID 'e50c0000-0000-0000-0000-000000000004'
\set groupCategoryID 'e50c0000-0000-0000-0000-000000000005'
\set groupID 'e50c0000-0000-0000-0000-000000000006'
\set userID 'e50c0000-0000-0000-0000-000000000007'

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

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should add a pending co-host and increment the revision
select is(
    sync_event_cohosts(
        :'userID'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid,
        array[:'cohostGroupID'::uuid],
        0
    )::jsonb @> '{"revision":1}'::jsonb,
    true,
    'Should add a pending co-host and increment the revision'
);

-- Should reject stale editor revisions
select throws_ok(
    format(
        'select sync_event_cohosts(%L::uuid, %L::uuid, %L::uuid, array[]::uuid[], 0)',
        :'userID',
        :'groupID',
        :'eventID'
    ),
    'OCG01',
    'co-hosts changed since this page was loaded; reload to continue',
    'Should reject stale editor revisions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
