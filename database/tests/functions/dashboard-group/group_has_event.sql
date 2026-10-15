-- Tests checking whether a group owns an available event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ea090000-0000-0000-0000-000000000001'
\set eventCategoryID 'ea090000-0000-0000-0000-000000000002'
\set eventDeletedID 'ea090000-0000-0000-0000-000000000003'
\set eventForeignID 'ea090000-0000-0000-0000-000000000004'
\set eventID 'ea090000-0000-0000-0000-000000000005'
\set eventMissingID 'ea090000-0000-0000-0000-000000000006'
\set groupCategoryID 'ea090000-0000-0000-0000-000000000007'
\set groupForeignID 'ea090000-0000-0000-0000-000000000008'
\set groupID 'ea090000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupForeignID', :'communityID', :'groupCategoryID');

-- Event owned by the group
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Deleted event owned by the group
select fx_event(:'eventDeletedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'deleted_at', current_timestamp
));

-- Event owned by another group
select fx_event(:'eventForeignID', :'groupForeignID', :'eventCategoryID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report deleted events as unavailable
select is(
    group_has_event(:'groupID', :'eventDeletedID'),
    false,
    'Should report deleted events as unavailable'
);

-- Should report events of another group as unavailable
select is(
    group_has_event(:'groupID', :'eventForeignID'),
    false,
    'Should report events of another group as unavailable'
);

-- Should report events owned by the group as available
select is(
    group_has_event(:'groupID', :'eventID'),
    true,
    'Should report events owned by the group as available'
);

-- Should report missing events as unavailable
select is(
    group_has_event(:'groupID', :'eventMissingID'),
    false,
    'Should report missing events as unavailable'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
