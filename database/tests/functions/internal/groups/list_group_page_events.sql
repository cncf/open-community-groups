-- Tests listing public group page events with approved co-hosted events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(1);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostedEventID 'e5050000-0000-0000-0000-000000000001'
\set cohostGroupID 'e5050000-0000-0000-0000-000000000002'
\set communityID 'e5050000-0000-0000-0000-000000000003'
\set eventCategoryID 'e5050000-0000-0000-0000-000000000004'
\set groupCategoryID 'e5050000-0000-0000-0000-000000000005'
\set ownerGroupID 'e5050000-0000-0000-0000-000000000006'
\set ownedEventID 'e5050000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups and events
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('slug', 'page-group'));
select fx_group(:'ownerGroupID', :'communityID', :'groupCategoryID');
select fx_event(:'cohostedEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));
select fx_event(:'ownedEventID', :'cohostGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Approved co-host row credited on the target group page
insert into event_cohost (
    approved_at,
    event_cohost_status_id,
    event_id,
    group_id
) values (
    current_timestamp,
    'approved',
    :'cohostedEventID',
    :'cohostGroupID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should include owned and approved co-hosted events once
select results_eq(
    format(
        $$
        select event_id
        from list_group_page_events(%L::uuid, 'page-group', array['in-person']::text[])
        order by starts_at
        $$,
        :'communityID'
    ),
    format(
        $$
        values
            (%L::uuid),
            (%L::uuid)
        $$,
        :'ownedEventID',
        :'cohostedEventID'
    ),
    'Should include owned and approved co-hosted events once'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
