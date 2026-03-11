-- Returns community statistics as a JSON object.
--
-- The function computes statistics for 4 domains: groups, members, events,
-- and attendees. Each domain includes the following stat types:
--
--   - total: Total count of entities
--   - total_by_*: Breakdown by category or region
--   - running_total: Cumulative total over time (all-time)
--   - running_total_by_*: Cumulative total by category or region (all-time)
--   - per_month: Monthly counts (last 2 years)
--   - per_month_by_*: Monthly counts by category or region (last 2 years)
--   - page_views.total_views/per_day_views/per_month_views: Page views
--
-- Time series data is returned as arrays of [timestamp, value] pairs, where
-- timestamps are Unix milliseconds. Category/region breakdowns use entity
-- names as keys.
create or replace function get_community_stats(p_community_id uuid)
returns json as $$
with params as (
    select
        p_community_id as community_id,
        current_date - interval '2 years' as period_start,
        current_date - interval '1 month' as recent_views_start
),
event_categories as (
    select
        ec.event_category_id,
        ec.name
    from event_category ec
    join params p on ec.community_id = p.community_id
),
group_categories as (
    select
        gc.group_category_id,
        gc.name
    from group_category gc
    join params p on gc.community_id = p.community_id
),
regions as (
    select
        r.region_id,
        r.name
    from region r
    join params p on r.community_id = p.community_id
),
filtered_groups as (
    select
        g.group_id,
        g.group_category_id,
        g.region_id,
        g.created_at,
        timezone('UTC', date_trunc('month', g.created_at at time zone 'UTC')) as created_month
    from "group" g
    join params p on true
    where g.community_id = p.community_id
        and g.active = true
        and g.deleted = false
),
members as (
    select
        gm.group_id,
        gm.created_at,
        fg.group_category_id,
        fg.region_id,
        timezone('UTC', date_trunc('month', gm.created_at at time zone 'UTC')) as created_month
    from group_member gm
    join filtered_groups fg on fg.group_id = gm.group_id
),
events as (
    select
        e.event_id,
        e.event_category_id,
        e.group_id,
        e.starts_at,
        fg.group_category_id,
        fg.region_id,
        timezone('UTC', date_trunc('month', e.starts_at at time zone 'UTC')) as starts_month
    from event e
    join filtered_groups fg on fg.group_id = e.group_id
    where e.published = true
        and e.canceled = false
        and e.deleted = false
),
events_for_views as (
    select
        e.event_id,
        e.event_category_id,
        fg.group_category_id,
        fg.region_id
    from event e
    join filtered_groups fg on fg.group_id = e.group_id
    where e.deleted = false
        and (e.canceled = true or e.published = true)
),
events_with_start as (
    select *
    from events
    where starts_at is not null
),
attendees as (
    select
        ea.event_id,
        ea.created_at,
        e.event_category_id,
        e.group_category_id,
        e.region_id,
        timezone('UTC', date_trunc('month', ea.created_at at time zone 'UTC')) as created_month
    from event_attendee ea
    join events e on e.event_id = ea.event_id
),
event_views_data as (
    select
        ev.event_id,
        ev.total,
        efv.event_category_id,
        efv.group_category_id,
        efv.region_id,
        timezone('UTC', date_trunc('month', ev.day::timestamp)) as viewed_month,
        ev.day
    from event_views ev
    join events_for_views efv on efv.event_id = ev.event_id
),
group_views_data as (
    select
        gv.group_id,
        gv.total,
        fg.group_category_id,
        fg.region_id,
        timezone('UTC', date_trunc('month', gv.day::timestamp)) as viewed_month,
        gv.day
    from group_views gv
    join filtered_groups fg on fg.group_id = gv.group_id
),
community_views_data as (
    select
        cv.total,
        timezone('UTC', date_trunc('month', cv.day::timestamp)) as viewed_month,
        cv.day
    from community_views cv
    join params p on cv.community_id = p.community_id
)
select json_strip_nulls(json_build_object(
    -- ========================================================================
    -- GROUPS STATISTICS
    -- ========================================================================
    'groups', json_build_object(
        'total', (select count(*)::int from filtered_groups),
        'total_by_category', coalesce((
            select json_agg(json_build_array(gc.name, stats.count) order by gc.name)
            from (
                select
                    fg.group_category_id,
                    count(*)::int as count
                from filtered_groups fg
                group by fg.group_category_id
            ) stats
            join group_categories gc on gc.group_category_id = stats.group_category_id
        ), '[]'::json),
        'total_by_region', coalesce((
            select json_agg(json_build_array(r.name, stats.count) order by r.name)
            from (
                select
                    fg.region_id,
                    count(*)::int as count
                from filtered_groups fg
                group by fg.region_id
            ) stats
            join regions r on r.region_id = stats.region_id
        ), '[]'::json),
        'running_total', coalesce((
            select json_agg(json_build_array(ts, cumulative_total) order by ts)
            from (
                select
                    floor(extract(epoch from month) * 1000)::bigint as ts,
                    sum(month_count) over (order by month) ::int as cumulative_total
                from (
                    select
                        fg.created_month as month,
                        count(*)::int as month_count
                    from filtered_groups fg
                    group by fg.created_month
                ) monthly
            ) totals
        ), '[]'::json),
        'running_total_by_category', coalesce((
            select json_object_agg(category_name, series order by category_name)
            from (
                select
                    category_name,
                    json_agg(json_build_array(ts, cumulative_total) order by ts) as series
                from (
                    select
                        gc.name as category_name,
                        floor(extract(epoch from month) * 1000)::bigint as ts,
                        sum(month_count) over (partition by gc.name order by month) ::int as cumulative_total
                    from (
                        select
                            fg.group_category_id,
                            fg.created_month as month,
                            count(*)::int as month_count
                        from filtered_groups fg
                        group by fg.group_category_id, fg.created_month
                    ) monthly
                    join group_categories gc on gc.group_category_id = monthly.group_category_id
                ) categorized
                group by category_name
            ) grouped
        ), '{}'::json),
        'running_total_by_region', coalesce((
            select json_object_agg(region_name, series order by region_name)
            from (
                select
                    region_name,
                    json_agg(json_build_array(ts, cumulative_total) order by ts) as series
                from (
                    select
                        r.name as region_name,
                        floor(extract(epoch from month) * 1000)::bigint as ts,
                        sum(month_count) over (partition by r.name order by month) ::int as cumulative_total
                    from (
                        select
                            fg.region_id,
                            fg.created_month as month,
                            count(*)::int as month_count
                        from filtered_groups fg
                        group by fg.region_id, fg.created_month
                    ) monthly
                    join regions r on r.region_id = monthly.region_id
                ) categorized
                group by region_name
            ) grouped
        ), '{}'::json),
        'per_month', coalesce((
            select json_agg(json_build_array(month_label, month_count) order by month_label)
            from (
                select
                    to_char(fg.created_month, 'YYYY-MM') as month_label,
                    count(*)::int as month_count
                from filtered_groups fg
                join params p on fg.created_at >= p.period_start
                group by to_char(fg.created_month, 'YYYY-MM')
            ) monthly
        ), '[]'::json),
        'per_month_by_category', coalesce((
            select json_object_agg(category_name, series order by category_name)
            from (
                select
                    category_name,
                    json_agg(json_build_array(month_label, month_count) order by month_label) as series
                from (
                    select
                        gc.name as category_name,
                        to_char(fg.created_month, 'YYYY-MM') as month_label,
                        count(*)::int as month_count
                    from filtered_groups fg
                    join params p on fg.created_at >= p.period_start
                    join group_categories gc on gc.group_category_id = fg.group_category_id
                    group by gc.name, to_char(fg.created_month, 'YYYY-MM')
                ) categorized
                group by category_name
            ) grouped
        ), '{}'::json),
        'per_month_by_region', coalesce((
            select json_object_agg(region_name, series order by region_name)
            from (
                select
                    region_name,
                    json_agg(json_build_array(month_label, month_count) order by month_label) as series
                from (
                    select
                        r.name as region_name,
                        to_char(fg.created_month, 'YYYY-MM') as month_label,
                        count(*)::int as month_count
                    from filtered_groups fg
                    join params p on fg.created_at >= p.period_start
                    join regions r on r.region_id = fg.region_id
                    group by r.name, to_char(fg.created_month, 'YYYY-MM')
                ) categorized
                group by region_name
            ) grouped
        ), '{}'::json)
    ),
    -- ========================================================================
    -- MEMBERS STATISTICS
    -- ========================================================================
    'members', json_build_object(
        'total', (select count(*)::int from members),
        'total_by_category', coalesce((
            select json_agg(json_build_array(gc.name, stats.count) order by gc.name)
            from (
                select
                    m.group_category_id,
                    count(*)::int as count
                from members m
                group by m.group_category_id
            ) stats
            join group_categories gc on gc.group_category_id = stats.group_category_id
        ), '[]'::json),
        'total_by_region', coalesce((
            select json_agg(json_build_array(r.name, stats.count) order by r.name)
            from (
                select
                    m.region_id,
                    count(*)::int as count
                from members m
                group by m.region_id
            ) stats
            join regions r on r.region_id = stats.region_id
        ), '[]'::json),
        'running_total', coalesce((
            select json_agg(json_build_array(ts, cumulative_total) order by ts)
            from (
                select
                    floor(extract(epoch from month) * 1000)::bigint as ts,
                    sum(month_count) over (order by month) ::int as cumulative_total
                from (
                    select
                        m.created_month as month,
                        count(*)::int as month_count
                    from members m
                    group by m.created_month
                ) monthly
            ) totals
        ), '[]'::json),
        'running_total_by_category', coalesce((
            select json_object_agg(category_name, series order by category_name)
            from (
                select
                    category_name,
                    json_agg(json_build_array(ts, cumulative_total) order by ts) as series
                from (
                    select
                        gc.name as category_name,
                        floor(extract(epoch from month) * 1000)::bigint as ts,
                        sum(month_count) over (partition by gc.name order by month) ::int as cumulative_total
                    from (
                        select
                            m.group_category_id,
                            m.created_month as month,
                            count(*)::int as month_count
                        from members m
                        group by m.group_category_id, m.created_month
                    ) monthly
                    join group_categories gc on gc.group_category_id = monthly.group_category_id
                ) categorized
                group by category_name
            ) grouped
        ), '{}'::json),
        'running_total_by_region', coalesce((
            select json_object_agg(region_name, series order by region_name)
            from (
                select
                    region_name,
                    json_agg(json_build_array(ts, cumulative_total) order by ts) as series
                from (
                    select
                        r.name as region_name,
                        floor(extract(epoch from month) * 1000)::bigint as ts,
                        sum(month_count) over (partition by r.name order by month) ::int as cumulative_total
                    from (
                        select
                            m.region_id,
                            m.created_month as month,
                            count(*)::int as month_count
                        from members m
                        group by m.region_id, m.created_month
                    ) monthly
                    join regions r on r.region_id = monthly.region_id
                ) categorized
                group by region_name
            ) grouped
        ), '{}'::json),
        'per_month', coalesce((
            select json_agg(json_build_array(month_label, month_count) order by month_label)
            from (
                select
                    to_char(m.created_month, 'YYYY-MM') as month_label,
                    count(*)::int as month_count
                from members m
                join params p on m.created_at >= p.period_start
                group by to_char(m.created_month, 'YYYY-MM')
            ) monthly
        ), '[]'::json),
        'per_month_by_category', coalesce((
            select json_object_agg(category_name, series order by category_name)
            from (
                select
                    category_name,
                    json_agg(json_build_array(month_label, month_count) order by month_label) as series
                from (
                    select
                        gc.name as category_name,
                        to_char(m.created_month, 'YYYY-MM') as month_label,
                        count(*)::int as month_count
                    from members m
                    join params p on m.created_at >= p.period_start
                    join group_categories gc on gc.group_category_id = m.group_category_id
                    group by gc.name, to_char(m.created_month, 'YYYY-MM')
                ) categorized
                group by category_name
            ) grouped
        ), '{}'::json),
        'per_month_by_region', coalesce((
            select json_object_agg(region_name, series order by region_name)
            from (
                select
                    region_name,
                    json_agg(json_build_array(month_label, month_count) order by month_label) as series
                from (
                    select
                        r.name as region_name,
                        to_char(m.created_month, 'YYYY-MM') as month_label,
                        count(*)::int as month_count
                    from members m
                    join params p on m.created_at >= p.period_start
                    join regions r on r.region_id = m.region_id
                    group by r.name, to_char(m.created_month, 'YYYY-MM')
                ) categorized
                group by region_name
            ) grouped
        ), '{}'::json)
    ),
    -- ========================================================================
    -- EVENTS STATISTICS
    -- ========================================================================
    'events', json_build_object(
        'total', (select count(*)::int from events),
        'total_by_event_category', coalesce((
            select json_agg(json_build_array(ec.name, stats.count) order by ec.name)
            from (
                select
                    e.event_category_id,
                    count(*)::int as count
                from events e
                group by e.event_category_id
            ) stats
            join event_categories ec on ec.event_category_id = stats.event_category_id
        ), '[]'::json),
        'total_by_group_category', coalesce((
            select json_agg(json_build_array(gc.name, stats.count) order by gc.name)
            from (
                select
                    e.group_category_id,
                    count(*)::int as count
                from events e
                group by e.group_category_id
            ) stats
            join group_categories gc on gc.group_category_id = stats.group_category_id
        ), '[]'::json),
        'total_by_group_region', coalesce((
            select json_agg(json_build_array(r.name, stats.count) order by r.name)
            from (
                select
                    e.region_id,
                    count(*)::int as count
                from events e
                group by e.region_id
            ) stats
            join regions r on r.region_id = stats.region_id
        ), '[]'::json),
        'running_total', coalesce((
            select json_agg(json_build_array(ts, cumulative_total) order by ts)
            from (
                select
                    floor(extract(epoch from month) * 1000)::bigint as ts,
                    sum(month_count) over (order by month) ::int as cumulative_total
                from (
                    select
                        ews.starts_month as month,
                        count(*)::int as month_count
                    from events_with_start ews
                    group by ews.starts_month
                ) monthly
            ) totals
        ), '[]'::json),
        'running_total_by_event_category', coalesce((
            select json_object_agg(category_name, series order by category_name)
            from (
                select
                    category_name,
                    json_agg(json_build_array(ts, cumulative_total) order by ts) as series
                from (
                    select
                        ec.name as category_name,
                        floor(extract(epoch from month) * 1000)::bigint as ts,
                        sum(month_count) over (partition by ec.name order by month) ::int as cumulative_total
                    from (
                        select
                            ews.event_category_id,
                            ews.starts_month as month,
                            count(*)::int as month_count
                        from events_with_start ews
                        group by ews.event_category_id, ews.starts_month
                    ) monthly
                    join event_categories ec on ec.event_category_id = monthly.event_category_id
                ) categorized
                group by category_name
            ) grouped
        ), '{}'::json),
        'running_total_by_group_category', coalesce((
            select json_object_agg(category_name, series order by category_name)
            from (
                select
                    category_name,
                    json_agg(json_build_array(ts, cumulative_total) order by ts) as series
                from (
                    select
                        gc.name as category_name,
                        floor(extract(epoch from month) * 1000)::bigint as ts,
                        sum(month_count) over (partition by gc.name order by month) ::int as cumulative_total
                    from (
                        select
                            ews.group_category_id,
                            ews.starts_month as month,
                            count(*)::int as month_count
                        from events_with_start ews
                        group by ews.group_category_id, ews.starts_month
                    ) monthly
                    join group_categories gc on gc.group_category_id = monthly.group_category_id
                ) categorized
                group by category_name
            ) grouped
        ), '{}'::json),
        'running_total_by_group_region', coalesce((
            select json_object_agg(region_name, series order by region_name)
            from (
                select
                    region_name,
                    json_agg(json_build_array(ts, cumulative_total) order by ts) as series
                from (
                    select
                        r.name as region_name,
                        floor(extract(epoch from month) * 1000)::bigint as ts,
                        sum(month_count) over (partition by r.name order by month) ::int as cumulative_total
                    from (
                        select
                            ews.region_id,
                            ews.starts_month as month,
                            count(*)::int as month_count
                        from events_with_start ews
                        group by ews.region_id, ews.starts_month
                    ) monthly
                    join regions r on r.region_id = monthly.region_id
                ) categorized
                group by region_name
            ) grouped
        ), '{}'::json),
        'per_month', coalesce((
            select json_agg(json_build_array(month_label, month_count) order by month_label)
            from (
                select
                    to_char(ews.starts_month, 'YYYY-MM') as month_label,
                    count(*)::int as month_count
                from events_with_start ews
                join params p on ews.starts_at >= p.period_start
                group by to_char(ews.starts_month, 'YYYY-MM')
            ) monthly
        ), '[]'::json),
        'per_month_by_event_category', coalesce((
            select json_object_agg(category_name, series order by category_name)
            from (
                select
                    category_name,
                    json_agg(json_build_array(month_label, month_count) order by month_label) as series
                from (
                    select
                        ec.name as category_name,
                        to_char(ews.starts_month, 'YYYY-MM') as month_label,
                        count(*)::int as month_count
                    from events_with_start ews
                    join params p on ews.starts_at >= p.period_start
                    join event_categories ec on ec.event_category_id = ews.event_category_id
                    group by ec.name, to_char(ews.starts_month, 'YYYY-MM')
                ) categorized
                group by category_name
            ) grouped
        ), '{}'::json),
        'per_month_by_group_category', coalesce((
            select json_object_agg(category_name, series order by category_name)
            from (
                select
                    category_name,
                    json_agg(json_build_array(month_label, month_count) order by month_label) as series
                from (
                    select
                        gc.name as category_name,
                        to_char(ews.starts_month, 'YYYY-MM') as month_label,
                        count(*)::int as month_count
                    from events_with_start ews
                    join params p on ews.starts_at >= p.period_start
                    join group_categories gc on gc.group_category_id = ews.group_category_id
                    group by gc.name, to_char(ews.starts_month, 'YYYY-MM')
                ) categorized
                group by category_name
            ) grouped
        ), '{}'::json),
        'per_month_by_group_region', coalesce((
            select json_object_agg(region_name, series order by region_name)
            from (
                select
                    region_name,
                    json_agg(json_build_array(month_label, month_count) order by month_label) as series
                from (
                    select
                        r.name as region_name,
                        to_char(ews.starts_month, 'YYYY-MM') as month_label,
                        count(*)::int as month_count
                    from events_with_start ews
                    join params p on ews.starts_at >= p.period_start
                    join regions r on r.region_id = ews.region_id
                    group by r.name, to_char(ews.starts_month, 'YYYY-MM')
                ) categorized
                group by region_name
            ) grouped
        ), '{}'::json)
    ),
    -- ========================================================================
    -- ATTENDEES STATISTICS
    -- ========================================================================
    'attendees', json_build_object(
        'total', (select count(*)::int from attendees),
        'total_by_event_category', coalesce((
            select json_agg(json_build_array(ec.name, stats.count) order by ec.name)
            from (
                select
                    a.event_category_id,
                    count(*)::int as count
                from attendees a
                group by a.event_category_id
            ) stats
            join event_categories ec on ec.event_category_id = stats.event_category_id
        ), '[]'::json),
        'total_by_group_category', coalesce((
            select json_agg(json_build_array(gc.name, stats.count) order by gc.name)
            from (
                select
                    a.group_category_id,
                    count(*)::int as count
                from attendees a
                group by a.group_category_id
            ) stats
            join group_categories gc on gc.group_category_id = stats.group_category_id
        ), '[]'::json),
        'total_by_group_region', coalesce((
            select json_agg(json_build_array(r.name, stats.count) order by r.name)
            from (
                select
                    a.region_id,
                    count(*)::int as count
                from attendees a
                group by a.region_id
            ) stats
            join regions r on r.region_id = stats.region_id
        ), '[]'::json),
        'running_total', coalesce((
            select json_agg(json_build_array(ts, cumulative_total) order by ts)
            from (
                select
                    floor(extract(epoch from month) * 1000)::bigint as ts,
                    sum(month_count) over (order by month) ::int as cumulative_total
                from (
                    select
                        a.created_month as month,
                        count(*)::int as month_count
                    from attendees a
                    group by a.created_month
                ) monthly
            ) totals
        ), '[]'::json),
        'running_total_by_event_category', coalesce((
            select json_object_agg(category_name, series order by category_name)
            from (
                select
                    category_name,
                    json_agg(json_build_array(ts, cumulative_total) order by ts) as series
                from (
                    select
                        ec.name as category_name,
                        floor(extract(epoch from month) * 1000)::bigint as ts,
                        sum(month_count) over (partition by ec.name order by month) ::int as cumulative_total
                    from (
                        select
                            a.event_category_id,
                            a.created_month as month,
                            count(*)::int as month_count
                        from attendees a
                        group by a.event_category_id, a.created_month
                    ) monthly
                    join event_categories ec on ec.event_category_id = monthly.event_category_id
                ) categorized
                group by category_name
            ) grouped
        ), '{}'::json),
        'running_total_by_group_category', coalesce((
            select json_object_agg(category_name, series order by category_name)
            from (
                select
                    category_name,
                    json_agg(json_build_array(ts, cumulative_total) order by ts) as series
                from (
                    select
                        gc.name as category_name,
                        floor(extract(epoch from month) * 1000)::bigint as ts,
                        sum(month_count) over (partition by gc.name order by month) ::int as cumulative_total
                    from (
                        select
                            a.group_category_id,
                            a.created_month as month,
                            count(*)::int as month_count
                        from attendees a
                        group by a.group_category_id, a.created_month
                    ) monthly
                    join group_categories gc on gc.group_category_id = monthly.group_category_id
                ) categorized
                group by category_name
            ) grouped
        ), '{}'::json),
        'running_total_by_group_region', coalesce((
            select json_object_agg(region_name, series order by region_name)
            from (
                select
                    region_name,
                    json_agg(json_build_array(ts, cumulative_total) order by ts) as series
                from (
                    select
                        r.name as region_name,
                        floor(extract(epoch from month) * 1000)::bigint as ts,
                        sum(month_count) over (partition by r.name order by month) ::int as cumulative_total
                    from (
                        select
                            a.region_id,
                            a.created_month as month,
                            count(*)::int as month_count
                        from attendees a
                        group by a.region_id, a.created_month
                    ) monthly
                    join regions r on r.region_id = monthly.region_id
                ) categorized
                group by region_name
            ) grouped
        ), '{}'::json),
        'per_month', coalesce((
            select json_agg(json_build_array(month_label, month_count) order by month_label)
            from (
                select
                    to_char(a.created_month, 'YYYY-MM') as month_label,
                    count(*)::int as month_count
                from attendees a
                join params p on a.created_at >= p.period_start
                group by to_char(a.created_month, 'YYYY-MM')
            ) monthly
        ), '[]'::json),
        'per_month_by_event_category', coalesce((
            select json_object_agg(category_name, series order by category_name)
            from (
                select
                    category_name,
                    json_agg(json_build_array(month_label, month_count) order by month_label) as series
                from (
                    select
                        ec.name as category_name,
                        to_char(a.created_month, 'YYYY-MM') as month_label,
                        count(*)::int as month_count
                    from attendees a
                    join params p on a.created_at >= p.period_start
                    join event_categories ec on ec.event_category_id = a.event_category_id
                    group by ec.name, to_char(a.created_month, 'YYYY-MM')
                ) categorized
                group by category_name
            ) grouped
        ), '{}'::json),
        'per_month_by_group_category', coalesce((
            select json_object_agg(category_name, series order by category_name)
            from (
                select
                    category_name,
                    json_agg(json_build_array(month_label, month_count) order by month_label) as series
                from (
                    select
                        gc.name as category_name,
                        to_char(a.created_month, 'YYYY-MM') as month_label,
                        count(*)::int as month_count
                    from attendees a
                    join params p on a.created_at >= p.period_start
                    join group_categories gc on gc.group_category_id = a.group_category_id
                    group by gc.name, to_char(a.created_month, 'YYYY-MM')
                ) categorized
                group by category_name
            ) grouped
        ), '{}'::json),
        'per_month_by_group_region', coalesce((
            select json_object_agg(region_name, series order by region_name)
            from (
                select
                    region_name,
                    json_agg(json_build_array(month_label, month_count) order by month_label) as series
                from (
                    select
                        r.name as region_name,
                        to_char(a.created_month, 'YYYY-MM') as month_label,
                        count(*)::int as month_count
                    from attendees a
                    join params p on a.created_at >= p.period_start
                    join regions r on r.region_id = a.region_id
                    group by r.name, to_char(a.created_month, 'YYYY-MM')
                ) categorized
                group by region_name
            ) grouped
        ), '{}'::json)
    ),
    -- ========================================================================
    -- PAGE VIEWS STATISTICS
    -- ========================================================================
    'page_views', json_build_object(
        'total_views', (
            select (
                coalesce((select sum(total) from community_views_data), 0) +
                coalesce((select sum(total) from event_views_data), 0) +
                coalesce((select sum(total) from group_views_data), 0)
            )::int
        ),
        'community', json_build_object(
            'total_views', (select coalesce(sum(total), 0)::int from community_views_data),
            'per_day_views', coalesce((
                select json_agg(json_build_array(day_label, day_count) order by day_label)
                from (
                    select
                        to_char(cv.day, 'YYYY-MM-DD') as day_label,
                        sum(cv.total)::int as day_count
                    from community_views_data cv
                    join params p on cv.day >= p.recent_views_start
                    group by to_char(cv.day, 'YYYY-MM-DD')
                ) daily
            ), '[]'::json),
            'per_month_views', coalesce((
                select json_agg(json_build_array(month_label, month_count) order by month_label)
                from (
                    select
                        to_char(cv.viewed_month, 'YYYY-MM') as month_label,
                        sum(cv.total)::int as month_count
                    from community_views_data cv
                    join params p on cv.day >= p.period_start
                    group by to_char(cv.viewed_month, 'YYYY-MM')
                ) monthly
            ), '[]'::json)
        ),
        'events', json_build_object(
            'total_views', (select coalesce(sum(total), 0)::int from event_views_data),
            'per_day_views', coalesce((
                select json_agg(json_build_array(day_label, day_count) order by day_label)
                from (
                    select
                        to_char(ev.day, 'YYYY-MM-DD') as day_label,
                        sum(ev.total)::int as day_count
                    from event_views_data ev
                    join params p on ev.day >= p.recent_views_start
                    group by to_char(ev.day, 'YYYY-MM-DD')
                ) daily
            ), '[]'::json),
            'per_month_views', coalesce((
                select json_agg(json_build_array(month_label, month_count) order by month_label)
                from (
                    select
                        to_char(ev.viewed_month, 'YYYY-MM') as month_label,
                        sum(ev.total)::int as month_count
                    from event_views_data ev
                    join params p on ev.day >= p.period_start
                    group by to_char(ev.viewed_month, 'YYYY-MM')
                ) monthly
            ), '[]'::json)
        ),
        'groups', json_build_object(
            'total_views', (select coalesce(sum(total), 0)::int from group_views_data),
            'per_day_views', coalesce((
                select json_agg(json_build_array(day_label, day_count) order by day_label)
                from (
                    select
                        to_char(gv.day, 'YYYY-MM-DD') as day_label,
                        sum(gv.total)::int as day_count
                    from group_views_data gv
                    join params p on gv.day >= p.recent_views_start
                    group by to_char(gv.day, 'YYYY-MM-DD')
                ) daily
            ), '[]'::json),
            'per_month_views', coalesce((
                select json_agg(json_build_array(month_label, month_count) order by month_label)
                from (
                    select
                        to_char(gv.viewed_month, 'YYYY-MM') as month_label,
                        sum(gv.total)::int as month_count
                    from group_views_data gv
                    join params p on gv.day >= p.period_start
                    group by to_char(gv.viewed_month, 'YYYY-MM')
                ) monthly
            ), '[]'::json)
        )
    )
));
$$ language sql;
