-- Returns group statistics as a JSON object.
--
-- The function computes statistics for 3 domains scoped to a single group:
--   - members
--   - events
--   - attendees
--
-- Each domain includes:
--   - total: Total count of entities
--   - running_total: Cumulative total over time (all-time)
--   - per_month: Monthly counts (last 2 years)
--
-- View metrics include:
--   - total_views: Total page views
--   - per_month_views: Monthly page views (last 2 years)
--
-- Time series data is returned as arrays of [timestamp/value] pairs where
-- timestamps are Unix milliseconds.
create or replace function get_group_stats(p_community_id uuid, p_group_id uuid)
returns json as $$
with params as (
    select
        p_community_id as community_id,
        p_group_id as group_id,
        current_date - interval '2 years' as period_start
),
filtered_group as (
    select g.group_id, g.community_id
    from "group" g
    join params p on g.group_id = p.group_id and g.community_id = p.community_id
    where g.active = true
        and g.deleted = false
),
members as (
    select
        gm.created_at,
        timezone('UTC', date_trunc('month', gm.created_at at time zone 'UTC')) as created_month
    from group_member gm
    join filtered_group fg on fg.group_id = gm.group_id
),
events as (
    select
        e.event_id,
        e.starts_at,
        timezone('UTC', date_trunc('month', e.starts_at at time zone 'UTC')) as starts_month
    from event e
    join filtered_group fg on fg.group_id = e.group_id
    where e.published = true
        and e.canceled = false
        and e.deleted = false
),
events_for_views as (
    select e.event_id
    from event e
    join filtered_group fg on fg.group_id = e.group_id
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
        ea.created_at,
        timezone('UTC', date_trunc('month', ea.created_at at time zone 'UTC')) as created_month
    from event_attendee ea
    join events e on e.event_id = ea.event_id
),
event_views_data as (
    select
        ev.total,
        timezone('UTC', date_trunc('month', ev.day::timestamp)) as viewed_month,
        ev.day
    from event_views ev
    join events_for_views efv on efv.event_id = ev.event_id
),
group_views_data as (
    select
        gv.total,
        timezone('UTC', date_trunc('month', gv.day::timestamp)) as viewed_month,
        gv.day
    from group_views gv
    join filtered_group fg on fg.group_id = gv.group_id
)
select json_strip_nulls(json_build_object(
    'group', json_build_object(
        'total_views', (select coalesce(sum(total), 0)::int from group_views_data),
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
    ),
    'members', json_build_object(
        'total', (select count(*)::int from members),
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
        ), '[]'::json)
    ),
    'events', json_build_object(
        'total', (select count(*)::int from events),
        'total_views', (select coalesce(sum(total), 0)::int from event_views_data),
        'running_total', coalesce((
            select json_agg(json_build_array(ts, cumulative_total) order by ts)
            from (
                select
                    floor(extract(epoch from month) * 1000)::bigint as ts,
                    sum(month_count) over (order by month) ::int as cumulative_total
                from (
                    select
                        e.starts_month as month,
                        count(*)::int as month_count
                    from events_with_start e
                    group by e.starts_month
                ) monthly
            ) totals
        ), '[]'::json),
        'per_month', coalesce((
            select json_agg(json_build_array(month_label, month_count) order by month_label)
            from (
                select
                    to_char(e.starts_month, 'YYYY-MM') as month_label,
                    count(*)::int as month_count
                from events_with_start e
                join params p on e.starts_at >= p.period_start
                group by to_char(e.starts_month, 'YYYY-MM')
            ) monthly
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
    'attendees', json_build_object(
        'total', (select count(*)::int from attendees),
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
        ), '[]'::json)
    )
));
$$ language sql stable;
