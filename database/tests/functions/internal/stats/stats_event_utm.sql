-- Tests all-time UTM attribution statistics of an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ea040000-0000-0000-0000-000000000001'
\set eventCategoryID 'ea040000-0000-0000-0000-000000000002'
\set eventCombinationsID 'ea040000-0000-0000-0000-000000000003'
\set eventEmptyID 'ea040000-0000-0000-0000-000000000004'
\set eventID 'ea040000-0000-0000-0000-000000000005'
\set groupCategoryID 'ea040000-0000-0000-0000-000000000006'
\set groupID 'ea040000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event with dimension values beyond the top 8
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Event with more than 10 combinations
select fx_event(:'eventCombinationsID', :'groupID', :'eventCategoryID');

-- Event without tagged views
select fx_event(:'eventEmptyID', :'groupID', :'eventCategoryID');

-- Tagged views with a literal other source, a campaign-only row and tied sources
insert into event_views_utm (event_id, day, total, utm_campaign, utm_medium, utm_source)
select :'eventID'::uuid, '2030-01-02'::date, 1, '', 'email', 'src-' || lpad(n::text, 2, '0')
from generate_series(1, 9) as n
union all
select :'eventID'::uuid, '2030-01-01'::date, 30, '', 'social', 'other'
union all
select :'eventID'::uuid, '2030-01-03'::date, 20, '', 'social', 'other'
union all
select :'eventID'::uuid, '2030-01-02'::date, 7, 'launch', '', '';

-- Tagged views spread over 12 combinations of one source
insert into event_views_utm (event_id, day, total, utm_campaign, utm_medium, utm_source)
select :'eventCombinationsID'::uuid, '2030-01-01'::date, 1, '', 'm-' || lpad(n::text, 3, '0'), 'news'
from generate_series(1, 11) as n
union all
select :'eventCombinationsID'::uuid, '2030-01-01'::date, 2, '', 'm-999', 'news';

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cap combinations at 10 ordered by views and identity
select is(
    (
        select jsonb_build_array(
            jsonb_array_length(utm->'combinations'),
            utm->'combinations'->0->>'utm_medium',
            utm->'combinations'->1->>'utm_medium',
            utm->'combinations'->9->>'utm_medium'
        )
        from (
            select stats_event_utm(e)::jsonb as utm
            from event e
            where e.event_id = :'eventCombinationsID'
        ) stats
    ),
    '[10, "m-999", "m-001", "m-009"]'::jsonb,
    'Should cap combinations at 10 ordered by views and identity'
);

-- Should count all tagged views
select is(
    (select (stats_event_utm(e)::jsonb->>'tagged_views')::int from event e where e.event_id = :'eventID'),
    66,
    'Should count all tagged views'
);

-- Should list combinations by views with their first and last days
select is(
    (
        select jsonb_path_query_array(
            stats_event_utm(e)::jsonb->'combinations',
            '$[0 to 2]'
        )
        from event e
        where e.event_id = :'eventID'
    ),
    '[
        {"first_day": "2030-01-01", "last_day": "2030-01-03", "views": 50, "utm_campaign": null, "utm_medium": "social", "utm_source": "other"},
        {"first_day": "2030-01-02", "last_day": "2030-01-02", "views": 7, "utm_campaign": "launch", "utm_medium": null, "utm_source": null},
        {"first_day": "2030-01-02", "last_day": "2030-01-02", "views": 1, "utm_campaign": null, "utm_medium": "email", "utm_source": "src-01"}
    ]'::jsonb,
    'Should list combinations by views with their first and last days'
);

-- Should rank campaigns and report views without a campaign
select is(
    (select stats_event_utm(e)::jsonb->'by_campaign' from event e where e.event_id = :'eventID'),
    '{
        "not_specified": 59,
        "remainder_count": 0,
        "remainder_views": 0,
        "values": [{"value": "launch", "views": 7}]
    }'::jsonb,
    'Should rank campaigns and report views without a campaign'
);

-- Should rank mediums and report views without a medium
select is(
    (select stats_event_utm(e)::jsonb->'by_medium' from event e where e.event_id = :'eventID'),
    '{
        "not_specified": 7,
        "remainder_count": 0,
        "remainder_views": 0,
        "values": [{"value": "social", "views": 50}, {"value": "email", "views": 9}]
    }'::jsonb,
    'Should rank mediums and report views without a medium'
);

-- Should rank the top 8 sources and group the remainder
select is(
    (select stats_event_utm(e)::jsonb->'by_source' from event e where e.event_id = :'eventID'),
    jsonb_build_object(
        'not_specified', 7,
        'remainder_count', 2,
        'remainder_views', 2,
        'values', (
            select jsonb_build_array(jsonb_build_object('value', 'other', 'views', 50))
                || jsonb_agg(
                    jsonb_build_object('value', 'src-' || lpad(n::text, 2, '0'), 'views', 1)
                    order by n
                )
            from generate_series(1, 7) as n
        )
    ),
    'Should rank the top 8 sources and group the remainder'
);

-- Should report the combinations beyond the cap
select is(
    (
        select jsonb_build_object(
            'combinations_remainder_views', utm->'combinations_remainder_views',
            'combinations_total_count', utm->'combinations_total_count'
        )
        from (
            select stats_event_utm(e)::jsonb as utm
            from event e
            where e.event_id = :'eventCombinationsID'
        ) stats
    ),
    '{"combinations_remainder_views": 2, "combinations_total_count": 12}'::jsonb,
    'Should report the combinations beyond the cap'
);

-- Should return empty statistics for events without tagged views
select is(
    (select stats_event_utm(e)::jsonb from event e where e.event_id = :'eventEmptyID'),
    '{
        "by_campaign": {"not_specified": 0, "remainder_count": 0, "remainder_views": 0, "values": []},
        "by_medium": {"not_specified": 0, "remainder_count": 0, "remainder_views": 0, "values": []},
        "by_source": {"not_specified": 0, "remainder_count": 0, "remainder_views": 0, "values": []},
        "combinations": [],
        "combinations_remainder_views": 0,
        "combinations_total_count": 0,
        "tagged_views": 0
    }'::jsonb,
    'Should return empty statistics for events without tagged views'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
