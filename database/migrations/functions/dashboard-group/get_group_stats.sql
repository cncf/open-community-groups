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
-- View metrics are grouped under page_views by total, group, and events and include:
--   - total_views: Total page views
--   - per_day_views: Daily page views (last month)
--   - per_month_views: Monthly page views (last 2 years)
--
-- Time series data is returned as arrays of [timestamp/value] pairs where
-- timestamps are Unix milliseconds.
create or replace function get_group_stats(p_alliance_id uuid, p_group_id uuid)
returns json as $$
with params as (
    select
        p_alliance_id as alliance_id,
        p_group_id as group_id,
        current_date - interval '2 years' as period_start,
        current_date - interval '1 month' as recent_views_start
),
filtered_group as (
    select g.group_id, g.alliance_id
    from "group" g
    join params p on g.group_id = p.group_id and g.alliance_id = p.alliance_id
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
        and e.test_event = false
),
events_for_views as (
    select e.event_id
    from event e
    join filtered_group fg on fg.group_id = e.group_id
    where e.deleted = false
        and e.published = true
        and e.test_event = false
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
    where ea.status = 'confirmed'
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
),
all_page_views_data as (
    select total, viewed_month, day
    from event_views_data
    union all
    select total, viewed_month, day
    from group_views_data
),
domain_running_total_counts as (
    select
        'members' as domain,
        m.created_month as bucket_start,
        count(*)::int as count
    from members m
    group by m.created_month

    union all

    select
        'events' as domain,
        e.starts_month as bucket_start,
        count(*)::int as count
    from events_with_start e
    group by e.starts_month

    union all

    select
        'attendees' as domain,
        a.created_month as bucket_start,
        count(*)::int as count
    from attendees a
    group by a.created_month
),
domain_monthly_counts as (
    select
        'members' as domain,
        to_char(m.created_month, 'YYYY-MM') as label,
        count(*)::int as count
    from members m
    join params p on m.created_at >= p.period_start
    group by to_char(m.created_month, 'YYYY-MM')

    union all

    select
        'events' as domain,
        to_char(e.starts_month, 'YYYY-MM') as label,
        count(*)::int as count
    from events_with_start e
    join params p on e.starts_at >= p.period_start
    group by to_char(e.starts_month, 'YYYY-MM')

    union all

    select
        'attendees' as domain,
        to_char(a.created_month, 'YYYY-MM') as label,
        count(*)::int as count
    from attendees a
    join params p on a.created_at >= p.period_start
    group by to_char(a.created_month, 'YYYY-MM')
),
page_view_total_counts as (
    select
        'total' as scope,
        coalesce(sum(apv.total), 0)::int as total_views
    from all_page_views_data apv

    union all

    select
        'events' as scope,
        coalesce(sum(ev.total), 0)::int as total_views
    from event_views_data ev

    union all

    select
        'group' as scope,
        coalesce(sum(gv.total), 0)::int as total_views
    from group_views_data gv
),
page_view_daily_counts as (
    select
        'total' as scope,
        to_char(apv.day, 'YYYY-MM-DD') as label,
        sum(apv.total)::int as count
    from all_page_views_data apv
    join params p on apv.day >= p.recent_views_start
    group by to_char(apv.day, 'YYYY-MM-DD')

    union all

    select
        'events' as scope,
        to_char(ev.day, 'YYYY-MM-DD') as label,
        sum(ev.total)::int as count
    from event_views_data ev
    join params p on ev.day >= p.recent_views_start
    group by to_char(ev.day, 'YYYY-MM-DD')

    union all

    select
        'group' as scope,
        to_char(gv.day, 'YYYY-MM-DD') as label,
        sum(gv.total)::int as count
    from group_views_data gv
    join params p on gv.day >= p.recent_views_start
    group by to_char(gv.day, 'YYYY-MM-DD')
),
page_view_monthly_counts as (
    select
        'total' as scope,
        to_char(apv.viewed_month, 'YYYY-MM') as label,
        sum(apv.total)::int as count
    from all_page_views_data apv
    join params p on apv.day >= p.period_start
    group by to_char(apv.viewed_month, 'YYYY-MM')

    union all

    select
        'events' as scope,
        to_char(ev.viewed_month, 'YYYY-MM') as label,
        sum(ev.total)::int as count
    from event_views_data ev
    join params p on ev.day >= p.period_start
    group by to_char(ev.viewed_month, 'YYYY-MM')

    union all

    select
        'group' as scope,
        to_char(gv.viewed_month, 'YYYY-MM') as label,
        sum(gv.total)::int as count
    from group_views_data gv
    join params p on gv.day >= p.period_start
    group by to_char(gv.viewed_month, 'YYYY-MM')
)
select json_strip_nulls(json_build_object(
    'members', json_build_object(
        'total', (select count(*)::int from members),
        'running_total', stats_running_total_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_running_total_counts counts
            where domain = 'members'
        )),
        'per_month', stats_label_count_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_monthly_counts counts
            where domain = 'members'
        ))
    ),
    'events', json_build_object(
        'total', (select count(*)::int from events),
        'running_total', stats_running_total_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_running_total_counts counts
            where domain = 'events'
        )),
        'per_month', stats_label_count_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_monthly_counts counts
            where domain = 'events'
        ))
    ),
    'attendees', json_build_object(
        'total', (select count(*)::int from attendees),
        'running_total', stats_running_total_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_running_total_counts counts
            where domain = 'attendees'
        )),
        'per_month', stats_label_count_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_monthly_counts counts
            where domain = 'attendees'
        ))
    ),
    'page_views', json_build_object(
        'total_views', (select total_views from page_view_total_counts where scope = 'total'),
        'total', json_build_object(
            'total_views', (select total_views from page_view_total_counts where scope = 'total'),
            'per_day_views', stats_label_count_series((
                select jsonb_agg(to_jsonb(counts))
                from page_view_daily_counts counts
                where scope = 'total'
            )),
            'per_month_views', stats_label_count_series((
                select jsonb_agg(to_jsonb(counts))
                from page_view_monthly_counts counts
                where scope = 'total'
            ))
        ),
        'events', json_build_object(
            'total_views', (select total_views from page_view_total_counts where scope = 'events'),
            'per_day_views', stats_label_count_series((
                select jsonb_agg(to_jsonb(counts))
                from page_view_daily_counts counts
                where scope = 'events'
            )),
            'per_month_views', stats_label_count_series((
                select jsonb_agg(to_jsonb(counts))
                from page_view_monthly_counts counts
                where scope = 'events'
            ))
        ),
        'group', json_build_object(
            'total_views', (select total_views from page_view_total_counts where scope = 'group'),
            'per_day_views', stats_label_count_series((
                select jsonb_agg(to_jsonb(counts))
                from page_view_daily_counts counts
                where scope = 'group'
            )),
            'per_month_views', stats_label_count_series((
                select jsonb_agg(to_jsonb(counts))
                from page_view_monthly_counts counts
                where scope = 'group'
            ))
        )
    )
));
$$ language sql stable;
