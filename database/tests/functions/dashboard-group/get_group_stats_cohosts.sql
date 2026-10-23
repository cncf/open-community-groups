-- Tests get_group_stats cohosted_events analytics.
-- Split from get_group_stats.sql because the co-host rows and subgroup seeded
-- here would change the exact stats payloads asserted in that file.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledCohostedEventID 'e5290000-0000-0000-0000-000000000001'
\set cohostedEventID 'e5290000-0000-0000-0000-000000000002'
\set communityID 'e5290000-0000-0000-0000-000000000003'
\set eventCategoryID 'e5290000-0000-0000-0000-000000000004'
\set groupCategoryID 'e5290000-0000-0000-0000-000000000005'
\set ownedEventID 'e5290000-0000-0000-0000-000000000006'
\set ownerGroupID 'e5290000-0000-0000-0000-000000000007'
\set pendingCohostedEventID 'e5290000-0000-0000-0000-00000000000d'
\set subgroupCohostedEvent2ID 'e5290000-0000-0000-0000-00000000000c'
\set subgroupCohostedEventID 'e5290000-0000-0000-0000-000000000008'
\set subgroupID 'e5290000-0000-0000-0000-000000000009'
\set subgroupOwnedEventID 'e5290000-0000-0000-0000-00000000000a'
\set targetGroupID 'e5290000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the co-hosted events
select fx_group(:'ownerGroupID', :'communityID', :'groupCategoryID');

-- Target group
select fx_group(:'targetGroupID', :'communityID', :'groupCategoryID');

-- Subgroup of the target group
select fx_group(:'subgroupID', :'communityID', :'groupCategoryID', jsonb_build_object('parent_group_id', :'targetGroupID'));

-- Canceled event co-hosted by the target group
select fx_event(:'canceledCohostedEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', current_timestamp + interval '4 days'
));

-- Event co-hosted by the target group, starting last month
select fx_event(:'cohostedEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', (date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '1 day') at time zone 'UTC'
));

-- Event owned by the target group
select fx_event(:'ownedEventID', :'targetGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

-- Event with a pending co-host invitation for the target group, starting last month
select fx_event(:'pendingCohostedEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', (date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '3 days') at time zone 'UTC'
));

-- Event co-hosted by the subgroup, starting two months ago
select fx_event(:'subgroupCohostedEventID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', (date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' + interval '1 day') at time zone 'UTC'
));

-- Second event co-hosted by the subgroup, starting last month
select fx_event(:'subgroupCohostedEvent2ID', :'ownerGroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', (date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' + interval '2 days') at time zone 'UTC'
));

-- Event owned by the subgroup and co-hosted by the target group
select fx_event(:'subgroupOwnedEventID', :'subgroupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '5 days'
));

-- Approved co-host rows for the target group and its subgroup
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id) values
    (current_timestamp, 'approved', :'canceledCohostedEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'cohostedEventID', :'targetGroupID'),
    (current_timestamp, 'approved', :'subgroupCohostedEvent2ID', :'subgroupID'),
    (current_timestamp, 'approved', :'subgroupCohostedEventID', :'subgroupID'),
    (current_timestamp, 'approved', :'subgroupOwnedEventID', :'targetGroupID');

-- Pending co-host row for the target group
insert into event_cohost (event_cohost_status_id, event_id, group_id) values
    ('pending', :'pendingCohostedEventID', :'targetGroupID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should bucket co-hosted events by month when including subgroups
select is(
    get_group_stats(:'communityID'::uuid, :'targetGroupID'::uuid, true)::jsonb->'cohosted_events',
    (
        -- Months of the seeded co-hosted events at UTC
        with months as (
            select
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '1 month' as m1,
                date_trunc('month', current_timestamp at time zone 'UTC') - interval '2 months' as m2
        )
        select jsonb_build_object(
            'total', 3,
            'running_total', jsonb_build_array(
                jsonb_build_array((extract(epoch from m2 at time zone 'UTC') * 1000)::bigint, 1),
                jsonb_build_array((extract(epoch from m1 at time zone 'UTC') * 1000)::bigint, 3)
            ),
            'per_month', jsonb_build_array(
                jsonb_build_array(to_char(m2, 'YYYY-MM'), 1),
                jsonb_build_array(to_char(m1, 'YYYY-MM'), 2)
            )
        )
        from months
    ),
    'Should bucket co-hosted events by month when including subgroups'
);

-- Should count only approved co-hosted events outside the owner scope without subgroups
select is(
    (get_group_stats(:'communityID'::uuid, :'targetGroupID'::uuid, false)::jsonb->'cohosted_events'->>'total')::int,
    2,
    'Should count only approved co-hosted events outside the owner scope without subgroups'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
