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
--   - page_views.total/community/groups/events: Page views
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
        and e.test_event = false
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
        ea.event_id,
        ea.created_at,
        e.event_category_id,
        e.group_category_id,
        e.region_id,
        timezone('UTC', date_trunc('month', ea.created_at at time zone 'UTC')) as created_month
    from event_attendee ea
    join events e on e.event_id = ea.event_id
    where ea.status = 'confirmed'
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
),
all_page_views_data as (
    select total, viewed_month, day
    from community_views_data
    union all
    select total, viewed_month, day
    from event_views_data
    union all
    select total, viewed_month, day
    from group_views_data
),
domain_running_total_counts as (
    select
        'groups' as domain,
        fg.created_month as bucket_start,
        count(*)::int as count
    from filtered_groups fg
    group by fg.created_month

    union all

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
        'groups' as domain,
        to_char(fg.created_month, 'YYYY-MM') as label,
        count(*)::int as count
    from filtered_groups fg
    join params p on fg.created_at >= p.period_start
    group by to_char(fg.created_month, 'YYYY-MM')

    union all

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
dimension_running_total_counts as (
    select
        'groups' as domain,
        'category' as dimension,
        gc.name as series_name,
        fg.created_month as bucket_start,
        count(*)::int as count
    from filtered_groups fg
    join group_categories gc on gc.group_category_id = fg.group_category_id
    group by gc.name, fg.created_month

    union all

    select
        'groups' as domain,
        'region' as dimension,
        r.name as series_name,
        fg.created_month as bucket_start,
        count(*)::int as count
    from filtered_groups fg
    join regions r on r.region_id = fg.region_id
    group by r.name, fg.created_month

    union all

    select
        'members' as domain,
        'category' as dimension,
        gc.name as series_name,
        m.created_month as bucket_start,
        count(*)::int as count
    from members m
    join group_categories gc on gc.group_category_id = m.group_category_id
    group by gc.name, m.created_month

    union all

    select
        'members' as domain,
        'region' as dimension,
        r.name as series_name,
        m.created_month as bucket_start,
        count(*)::int as count
    from members m
    join regions r on r.region_id = m.region_id
    group by r.name, m.created_month

    union all

    select
        'events' as domain,
        'event_category' as dimension,
        ec.name as series_name,
        e.starts_month as bucket_start,
        count(*)::int as count
    from events_with_start e
    join event_categories ec on ec.event_category_id = e.event_category_id
    group by ec.name, e.starts_month

    union all

    select
        'events' as domain,
        'group_category' as dimension,
        gc.name as series_name,
        e.starts_month as bucket_start,
        count(*)::int as count
    from events_with_start e
    join group_categories gc on gc.group_category_id = e.group_category_id
    group by gc.name, e.starts_month

    union all

    select
        'events' as domain,
        'group_region' as dimension,
        r.name as series_name,
        e.starts_month as bucket_start,
        count(*)::int as count
    from events_with_start e
    join regions r on r.region_id = e.region_id
    group by r.name, e.starts_month

    union all

    select
        'attendees' as domain,
        'event_category' as dimension,
        ec.name as series_name,
        a.created_month as bucket_start,
        count(*)::int as count
    from attendees a
    join event_categories ec on ec.event_category_id = a.event_category_id
    group by ec.name, a.created_month

    union all

    select
        'attendees' as domain,
        'group_category' as dimension,
        gc.name as series_name,
        a.created_month as bucket_start,
        count(*)::int as count
    from attendees a
    join group_categories gc on gc.group_category_id = a.group_category_id
    group by gc.name, a.created_month

    union all

    select
        'attendees' as domain,
        'group_region' as dimension,
        r.name as series_name,
        a.created_month as bucket_start,
        count(*)::int as count
    from attendees a
    join regions r on r.region_id = a.region_id
    group by r.name, a.created_month
),
dimension_monthly_counts as (
    select
        'groups' as domain,
        'category' as dimension,
        gc.name as series_name,
        to_char(fg.created_month, 'YYYY-MM') as label,
        count(*)::int as count
    from filtered_groups fg
    join params p on fg.created_at >= p.period_start
    join group_categories gc on gc.group_category_id = fg.group_category_id
    group by gc.name, to_char(fg.created_month, 'YYYY-MM')

    union all

    select
        'groups' as domain,
        'region' as dimension,
        r.name as series_name,
        to_char(fg.created_month, 'YYYY-MM') as label,
        count(*)::int as count
    from filtered_groups fg
    join params p on fg.created_at >= p.period_start
    join regions r on r.region_id = fg.region_id
    group by r.name, to_char(fg.created_month, 'YYYY-MM')

    union all

    select
        'members' as domain,
        'category' as dimension,
        gc.name as series_name,
        to_char(m.created_month, 'YYYY-MM') as label,
        count(*)::int as count
    from members m
    join params p on m.created_at >= p.period_start
    join group_categories gc on gc.group_category_id = m.group_category_id
    group by gc.name, to_char(m.created_month, 'YYYY-MM')

    union all

    select
        'members' as domain,
        'region' as dimension,
        r.name as series_name,
        to_char(m.created_month, 'YYYY-MM') as label,
        count(*)::int as count
    from members m
    join params p on m.created_at >= p.period_start
    join regions r on r.region_id = m.region_id
    group by r.name, to_char(m.created_month, 'YYYY-MM')

    union all

    select
        'events' as domain,
        'event_category' as dimension,
        ec.name as series_name,
        to_char(e.starts_month, 'YYYY-MM') as label,
        count(*)::int as count
    from events_with_start e
    join params p on e.starts_at >= p.period_start
    join event_categories ec on ec.event_category_id = e.event_category_id
    group by ec.name, to_char(e.starts_month, 'YYYY-MM')

    union all

    select
        'events' as domain,
        'group_category' as dimension,
        gc.name as series_name,
        to_char(e.starts_month, 'YYYY-MM') as label,
        count(*)::int as count
    from events_with_start e
    join params p on e.starts_at >= p.period_start
    join group_categories gc on gc.group_category_id = e.group_category_id
    group by gc.name, to_char(e.starts_month, 'YYYY-MM')

    union all

    select
        'events' as domain,
        'group_region' as dimension,
        r.name as series_name,
        to_char(e.starts_month, 'YYYY-MM') as label,
        count(*)::int as count
    from events_with_start e
    join params p on e.starts_at >= p.period_start
    join regions r on r.region_id = e.region_id
    group by r.name, to_char(e.starts_month, 'YYYY-MM')

    union all

    select
        'attendees' as domain,
        'event_category' as dimension,
        ec.name as series_name,
        to_char(a.created_month, 'YYYY-MM') as label,
        count(*)::int as count
    from attendees a
    join params p on a.created_at >= p.period_start
    join event_categories ec on ec.event_category_id = a.event_category_id
    group by ec.name, to_char(a.created_month, 'YYYY-MM')

    union all

    select
        'attendees' as domain,
        'group_category' as dimension,
        gc.name as series_name,
        to_char(a.created_month, 'YYYY-MM') as label,
        count(*)::int as count
    from attendees a
    join params p on a.created_at >= p.period_start
    join group_categories gc on gc.group_category_id = a.group_category_id
    group by gc.name, to_char(a.created_month, 'YYYY-MM')

    union all

    select
        'attendees' as domain,
        'group_region' as dimension,
        r.name as series_name,
        to_char(a.created_month, 'YYYY-MM') as label,
        count(*)::int as count
    from attendees a
    join params p on a.created_at >= p.period_start
    join regions r on r.region_id = a.region_id
    group by r.name, to_char(a.created_month, 'YYYY-MM')
),
page_view_total_counts as (
    select
        'total' as scope,
        coalesce(sum(apv.total), 0)::int as total_views
    from all_page_views_data apv

    union all

    select
        'community' as scope,
        coalesce(sum(cv.total), 0)::int as total_views
    from community_views_data cv

    union all

    select
        'events' as scope,
        coalesce(sum(ev.total), 0)::int as total_views
    from event_views_data ev

    union all

    select
        'groups' as scope,
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
        'community' as scope,
        to_char(cv.day, 'YYYY-MM-DD') as label,
        sum(cv.total)::int as count
    from community_views_data cv
    join params p on cv.day >= p.recent_views_start
    group by to_char(cv.day, 'YYYY-MM-DD')

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
        'groups' as scope,
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
        'community' as scope,
        to_char(cv.viewed_month, 'YYYY-MM') as label,
        sum(cv.total)::int as count
    from community_views_data cv
    join params p on cv.day >= p.period_start
    group by to_char(cv.viewed_month, 'YYYY-MM')

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
        'groups' as scope,
        to_char(gv.viewed_month, 'YYYY-MM') as label,
        sum(gv.total)::int as count
    from group_views_data gv
    join params p on gv.day >= p.period_start
    group by to_char(gv.viewed_month, 'YYYY-MM')
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
        'running_total', stats_running_total_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_running_total_counts counts
            where domain = 'groups'
        )),
        'running_total_by_category', coalesce((
            select stats_running_total_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_running_total_counts counts
            where domain = 'groups'
            and dimension = 'category'
        ), '{}'::json),
        'running_total_by_region', coalesce((
            select stats_running_total_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_running_total_counts counts
            where domain = 'groups'
            and dimension = 'region'
        ), '{}'::json),
        'per_month', stats_label_count_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_monthly_counts counts
            where domain = 'groups'
        )),
        'per_month_by_category', coalesce((
            select stats_label_count_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_monthly_counts counts
            where domain = 'groups'
            and dimension = 'category'
        ), '{}'::json),
        'per_month_by_region', coalesce((
            select stats_label_count_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_monthly_counts counts
            where domain = 'groups'
            and dimension = 'region'
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
        'running_total', stats_running_total_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_running_total_counts counts
            where domain = 'members'
        )),
        'running_total_by_category', coalesce((
            select stats_running_total_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_running_total_counts counts
            where domain = 'members'
            and dimension = 'category'
        ), '{}'::json),
        'running_total_by_region', coalesce((
            select stats_running_total_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_running_total_counts counts
            where domain = 'members'
            and dimension = 'region'
        ), '{}'::json),
        'per_month', stats_label_count_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_monthly_counts counts
            where domain = 'members'
        )),
        'per_month_by_category', coalesce((
            select stats_label_count_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_monthly_counts counts
            where domain = 'members'
            and dimension = 'category'
        ), '{}'::json),
        'per_month_by_region', coalesce((
            select stats_label_count_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_monthly_counts counts
            where domain = 'members'
            and dimension = 'region'
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
        'running_total', stats_running_total_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_running_total_counts counts
            where domain = 'events'
        )),
        'running_total_by_event_category', coalesce((
            select stats_running_total_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_running_total_counts counts
            where domain = 'events'
            and dimension = 'event_category'
        ), '{}'::json),
        'running_total_by_group_category', coalesce((
            select stats_running_total_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_running_total_counts counts
            where domain = 'events'
            and dimension = 'group_category'
        ), '{}'::json),
        'running_total_by_group_region', coalesce((
            select stats_running_total_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_running_total_counts counts
            where domain = 'events'
            and dimension = 'group_region'
        ), '{}'::json),
        'per_month', stats_label_count_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_monthly_counts counts
            where domain = 'events'
        )),
        'per_month_by_event_category', coalesce((
            select stats_label_count_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_monthly_counts counts
            where domain = 'events'
            and dimension = 'event_category'
        ), '{}'::json),
        'per_month_by_group_category', coalesce((
            select stats_label_count_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_monthly_counts counts
            where domain = 'events'
            and dimension = 'group_category'
        ), '{}'::json),
        'per_month_by_group_region', coalesce((
            select stats_label_count_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_monthly_counts counts
            where domain = 'events'
            and dimension = 'group_region'
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
        'running_total', stats_running_total_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_running_total_counts counts
            where domain = 'attendees'
        )),
        'running_total_by_event_category', coalesce((
            select stats_running_total_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_running_total_counts counts
            where domain = 'attendees'
            and dimension = 'event_category'
        ), '{}'::json),
        'running_total_by_group_category', coalesce((
            select stats_running_total_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_running_total_counts counts
            where domain = 'attendees'
            and dimension = 'group_category'
        ), '{}'::json),
        'running_total_by_group_region', coalesce((
            select stats_running_total_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_running_total_counts counts
            where domain = 'attendees'
            and dimension = 'group_region'
        ), '{}'::json),
        'per_month', stats_label_count_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_monthly_counts counts
            where domain = 'attendees'
        )),
        'per_month_by_event_category', coalesce((
            select stats_label_count_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_monthly_counts counts
            where domain = 'attendees'
            and dimension = 'event_category'
        ), '{}'::json),
        'per_month_by_group_category', coalesce((
            select stats_label_count_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_monthly_counts counts
            where domain = 'attendees'
            and dimension = 'group_category'
        ), '{}'::json),
        'per_month_by_group_region', coalesce((
            select stats_label_count_series_by_name(jsonb_agg(to_jsonb(counts)))
            from dimension_monthly_counts counts
            where domain = 'attendees'
            and dimension = 'group_region'
        ), '{}'::json)
    ),
    -- ========================================================================
    -- PAGE VIEWS STATISTICS
    -- ========================================================================
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
        'community', json_build_object(
            'total_views', (select total_views from page_view_total_counts where scope = 'community'),
            'per_day_views', stats_label_count_series((
                select jsonb_agg(to_jsonb(counts))
                from page_view_daily_counts counts
                where scope = 'community'
            )),
            'per_month_views', stats_label_count_series((
                select jsonb_agg(to_jsonb(counts))
                from page_view_monthly_counts counts
                where scope = 'community'
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
        'groups', json_build_object(
            'total_views', (select total_views from page_view_total_counts where scope = 'groups'),
            'per_day_views', stats_label_count_series((
                select jsonb_agg(to_jsonb(counts))
                from page_view_daily_counts counts
                where scope = 'groups'
            )),
            'per_month_views', stats_label_count_series((
                select jsonb_agg(to_jsonb(counts))
                from page_view_monthly_counts counts
                where scope = 'groups'
            ))
        )
    )
));
$$ language sql;
