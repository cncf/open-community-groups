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
-- because summing an empty set returns null. The shared stats_timeline helper
-- builds each domain from its buckets.
create or replace function get_site_stats()
returns json as $$
-- Start the reporting period ten years ago
with params as (
    select current_date - interval '10 years' as period_start
),
-- Select active groups of active communities
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
-- Select published non-test events of those groups that were not canceled
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
)
-- Build each domain timeline from its buckets
select json_strip_nulls(json_build_object(
    'attendees', stats_timeline(
        (select jsonb_agg(to_jsonb(b)) from attendee_buckets b),
        true
    ),
    'events', stats_timeline(
        (select jsonb_agg(to_jsonb(b)) from event_buckets b),
        true
    ),
    'groups', stats_timeline(
        (select jsonb_agg(to_jsonb(b)) from group_buckets b),
        true
    ),
    'members', stats_timeline(
        (select jsonb_agg(to_jsonb(b)) from member_buckets b),
        true
    )
));
$$ language sql stable;
