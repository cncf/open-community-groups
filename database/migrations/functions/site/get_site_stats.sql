-- Returns site statistics as a JSON object.
--
-- The function computes statistics for 4 domains: groups, members, events,
-- and attendees. Each domain includes the following stat types:
--
--   - total: Total count of entities (all-time)
--   - running_total: Cumulative total over time (last 10 years)
--   - per_month: Monthly counts (last 10 years)
--
-- Time series data is returned as arrays of [timestamp, value] pairs, where
-- timestamps are Unix milliseconds. Monthly data uses YYYY-MM labels.
create or replace function get_site_stats()
returns json as $$
with params as (
    select current_date - interval '10 years' as period_start
),
filtered_groups as (
    select
        g.created_at,
        g.group_category_id,
        g.group_id,
        g.region_id,

        timezone(
            'UTC',
            date_trunc('month', g.created_at at time zone 'UTC')
        ) as created_month
    from "group" g
    where g.active = true
        and g.deleted = false
),
members as (
    select
        gm.created_at,
        fg.group_category_id,
        fg.group_id,
        fg.region_id,

        timezone(
            'UTC',
            date_trunc('month', gm.created_at at time zone 'UTC')
        ) as created_month
    from group_member gm
    join filtered_groups fg on fg.group_id = gm.group_id
),
events as (
    select
        e.event_category_id,
        e.event_id,
        e.group_id,
        e.starts_at,
        fg.group_category_id,
        fg.region_id,

        timezone(
            'UTC',
            date_trunc('month', e.starts_at at time zone 'UTC')
        ) as starts_month
    from event e
    join filtered_groups fg on fg.group_id = e.group_id
    where e.canceled = false
        and e.deleted = false
        and e.published = true
),
events_with_start as (
    select *
    from events
    where starts_at is not null
),
attendees as (
    select
        ea.created_at,
        ea.event_id,
        e.event_category_id,
        e.group_category_id,
        e.region_id,

        timezone(
            'UTC',
            date_trunc('month', ea.created_at at time zone 'UTC')
        ) as created_month
    from event_attendee ea
    join events e on e.event_id = ea.event_id
)
select json_strip_nulls(json_build_object(
    'groups', json_build_object(
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
                    join params p on fg.created_at >= p.period_start
                    group by fg.created_month
                ) monthly
            ) totals
        ), '[]'::json),
        'total', (select count(*)::int from filtered_groups)
    ),
    'members', json_build_object(
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
                    join params p on m.created_at >= p.period_start
                    group by m.created_month
                ) monthly
            ) totals
        ), '[]'::json),
        'total', (select count(*)::int from members)
    ),
    'events', json_build_object(
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
                    join params p on ews.starts_at >= p.period_start
                    group by ews.starts_month
                ) monthly
            ) totals
        ), '[]'::json),
        'total', (select count(*)::int from events)
    ),
    'attendees', json_build_object(
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
                    join params p on a.created_at >= p.period_start
                    group by a.created_month
                ) monthly
            ) totals
        ), '[]'::json),
        'total', (select count(*)::int from attendees)
    )
));
$$ language sql;
