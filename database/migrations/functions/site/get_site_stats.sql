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
    join alliance c on c.alliance_id = g.alliance_id
    where c.active = true
        and g.active = true
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
    where ea.status = 'confirmed'
),
domain_running_total_counts as (
    select
        'groups' as domain,
        fg.created_month as bucket_start,
        count(*)::int as count
    from filtered_groups fg
    join params p on fg.created_at >= p.period_start
    group by fg.created_month

    union all

    select
        'members' as domain,
        m.created_month as bucket_start,
        count(*)::int as count
    from members m
    join params p on m.created_at >= p.period_start
    group by m.created_month

    union all

    select
        'events' as domain,
        ews.starts_month as bucket_start,
        count(*)::int as count
    from events_with_start ews
    join params p on ews.starts_at >= p.period_start
    group by ews.starts_month

    union all

    select
        'attendees' as domain,
        a.created_month as bucket_start,
        count(*)::int as count
    from attendees a
    join params p on a.created_at >= p.period_start
    group by a.created_month
),
domain_monthly_counts as (
    select
        domain,
        to_char(bucket_start, 'YYYY-MM') as label,
        count
    from domain_running_total_counts
)
select json_strip_nulls(json_build_object(
    'groups', json_build_object(
        'per_month', stats_label_count_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_monthly_counts counts
            where domain = 'groups'
        )),
        'running_total', stats_running_total_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_running_total_counts counts
            where domain = 'groups'
        )),
        'total', (select count(*)::int from filtered_groups)
    ),
    'members', json_build_object(
        'per_month', stats_label_count_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_monthly_counts counts
            where domain = 'members'
        )),
        'running_total', stats_running_total_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_running_total_counts counts
            where domain = 'members'
        )),
        'total', (select count(*)::int from members)
    ),
    'events', json_build_object(
        'per_month', stats_label_count_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_monthly_counts counts
            where domain = 'events'
        )),
        'running_total', stats_running_total_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_running_total_counts counts
            where domain = 'events'
        )),
        'total', (select count(*)::int from events)
    ),
    'attendees', json_build_object(
        'per_month', stats_label_count_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_monthly_counts counts
            where domain = 'attendees'
        )),
        'running_total', stats_running_total_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_running_total_counts counts
            where domain = 'attendees'
        )),
        'total', (select count(*)::int from attendees)
    )
));
$$ language sql;
