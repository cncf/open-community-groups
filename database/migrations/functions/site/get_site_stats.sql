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
--
-- Each domain is scanned once into monthly buckets split at the period start,
-- so totals and series come from the same aggregation. Totals default to zero
-- because summing an empty set returns null.
create or replace function get_site_stats()
returns json as $$
with params as (
    select current_date - interval '10 years' as period_start
),
filtered_groups as (
    select
        g.created_at,
        g.group_id
    from "group" g
    join community c on c.community_id = g.community_id
    where c.active = true
        and g.active = true
        and g.deleted = false
),
events as (
    select
        e.event_id,
        e.starts_at
    from event e
    join filtered_groups fg on fg.group_id = e.group_id
    where e.canceled = false
        and e.deleted = false
        and e.published = true
        and e.test_event = false
),
-- Aggregate each domain once into monthly buckets split at the period start
group_buckets as (
    select
        timezone(
            'UTC',
            date_trunc('month', fg.created_at at time zone 'UTC')
        ) as bucket_start,
        fg.created_at >= p.period_start as in_period,
        count(*) as count
    from filtered_groups fg
    cross join params p
    group by 1, 2
),
member_buckets as (
    select
        timezone(
            'UTC',
            date_trunc('month', gm.created_at at time zone 'UTC')
        ) as bucket_start,
        gm.created_at >= p.period_start as in_period,
        count(*) as count
    from group_member gm
    join filtered_groups fg on fg.group_id = gm.group_id
    cross join params p
    group by 1, 2
),
event_buckets as (
    -- Undated events land in a null bucket that only counts in totals
    select
        timezone(
            'UTC',
            date_trunc('month', e.starts_at at time zone 'UTC')
        ) as bucket_start,
        e.starts_at >= p.period_start as in_period,
        count(*) as count
    from events e
    cross join params p
    group by 1, 2
),
attendee_buckets as (
    select
        timezone(
            'UTC',
            date_trunc('month', ea.created_at at time zone 'UTC')
        ) as bucket_start,
        ea.created_at >= p.period_start as in_period,
        count(*) as count
    from event_attendee ea
    join events e on e.event_id = ea.event_id
    cross join params p
    where ea.status = 'confirmed'
    group by 1, 2
),
domain_running_total_counts as (
    select
        'groups' as domain,
        gb.bucket_start,
        sum(gb.count)::int as count
    from group_buckets gb
    where gb.in_period
    group by gb.bucket_start

    union all

    select
        'members' as domain,
        mb.bucket_start,
        sum(mb.count)::int as count
    from member_buckets mb
    where mb.in_period
    group by mb.bucket_start

    union all

    select
        'events' as domain,
        eb.bucket_start,
        sum(eb.count)::int as count
    from event_buckets eb
    where eb.in_period
    group by eb.bucket_start

    union all

    select
        'attendees' as domain,
        ab.bucket_start,
        sum(ab.count)::int as count
    from attendee_buckets ab
    where ab.in_period
    group by ab.bucket_start
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
        'total', (select coalesce(sum(count), 0)::int from group_buckets)
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
        'total', (select coalesce(sum(count), 0)::int from member_buckets)
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
        'total', (select coalesce(sum(count), 0)::int from event_buckets)
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
        'total', (select coalesce(sum(count), 0)::int from attendee_buckets)
    )
));
$$ language sql;
