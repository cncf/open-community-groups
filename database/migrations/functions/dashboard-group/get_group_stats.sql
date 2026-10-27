-- Returns group statistics as a JSON object.
--
-- The function computes statistics for 4 domains scoped to a single group or
-- to a group and its active subgroups:
--   - members
--   - events
--   - cohosted_events
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
create or replace function get_group_stats(
    p_community_id uuid,
    p_group_id uuid,
    p_include_subgroups boolean
)
returns json as $$
-- Resolve the scope arguments and reporting windows
with params as (
    select
        p_community_id as community_id,
        p_group_id as group_id,
        p_include_subgroups as include_subgroups,
        current_date - interval '2 years' as period_start,
        current_date - interval '1 month' as recent_views_start
),
-- Resolve the target group and, when requested, its subgroups
scoped_groups as (
    select s.group_id
    from params p
    cross join lateral list_group_scope_ids(p.community_id, p.group_id, p.include_subgroups) s
),
-- Count each member once at their earliest membership in scope
unique_members as (
    select
        gm.user_id,
        min(gm.created_at) as first_seen_at
    from group_member gm
    join scoped_groups sg on sg.group_id = gm.group_id
    group by gm.user_id
),
-- Select published non-test events of the scope that were not canceled
events as (
    select
        e.event_id,
        e.starts_at
    from event e
    join scoped_groups sg on sg.group_id = e.group_id
    where e.published = true
        and e.canceled = false
        and e.deleted = false
        and e.test_event = false
),
-- Select approved co-hosted events owned by active groups outside the scope
cohosted_events as (
    select distinct
        e.event_id,
        e.starts_at
    from event_cohost ec
    join scoped_groups sg on sg.group_id = ec.group_id
    join event e using (event_id)
    join "group" owner_group on owner_group.group_id = e.group_id
    join community owner_community on owner_community.community_id = owner_group.community_id
    where ec.event_cohost_status_id = 'approved'
        and e.published = true
        and e.canceled = false
        and e.deleted = false
        and e.test_event = false
        and not exists (
            select 1
            from scoped_groups owner_scope
            where owner_scope.group_id = e.group_id
        )
        and owner_community.active = true
        and owner_group.active = true
        and owner_group.deleted = false
),
-- Select published non-test events of the scope, canceled included, for views
events_for_views as (
    select e.event_id
    from event e
    join scoped_groups sg on sg.group_id = e.group_id
    where e.deleted = false
        and e.published = true
        and e.test_event = false
),
-- Select confirmed attendees of the scope events
attendees as (
    select ea.created_at
    from event_attendee ea
    join events e on e.event_id = ea.event_id
    where ea.status = 'confirmed'
),
-- Aggregate each domain once into monthly buckets split at the period start
member_buckets as (
    select
        timezone(
            'UTC',
            date_trunc('month', um.first_seen_at at time zone 'UTC')
        ) as bucket_start,
        um.first_seen_at >= p.period_start as in_period,
        count(*)::int as count
    from unique_members um
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
        count(*)::int as count
    from events e
    cross join params p
    group by 1, 2
),
cohosted_event_buckets as (
    -- Undated events land in a null bucket that only counts in totals
    select
        timezone(
            'UTC',
            date_trunc('month', ce.starts_at at time zone 'UTC')
        ) as bucket_start,
        ce.starts_at >= p.period_start as in_period,
        count(*)::int as count
    from cohosted_events ce
    cross join params p
    group by 1, 2
),
attendee_buckets as (
    select
        timezone(
            'UTC',
            date_trunc('month', a.created_at at time zone 'UTC')
        ) as bucket_start,
        a.created_at >= p.period_start as in_period,
        count(*)::int as count
    from attendees a
    cross join params p
    group by 1, 2
),
-- Sum event page views by day into parallel arrays
event_view_days as (
    select
        array_agg(d.day) as days,
        array_agg(d.total) as totals
    from (
        select
            ev.day,
            sum(ev.total)::int as total
        from event_views ev
        join events_for_views efv on efv.event_id = ev.event_id
        group by ev.day
    ) d
),
-- Sum group page views by day into parallel arrays
group_view_days as (
    select
        array_agg(d.day) as days,
        array_agg(d.total) as totals
    from (
        select
            gv.day,
            sum(gv.total)::int as total
        from group_views gv
        join scoped_groups sg on sg.group_id = gv.group_id
        group by gv.day
    ) d
),
-- Build the page views block of each scope, the total one from both scopes
page_view_blocks as (
    select
        stats_page_views(
            evd.days,
            evd.totals,
            p.period_start::date,
            p.recent_views_start::date
        ) as events_block,
        stats_page_views(
            gvd.days,
            gvd.totals,
            p.period_start::date,
            p.recent_views_start::date
        ) as group_block,
        stats_page_views(
            evd.days || gvd.days,
            evd.totals || gvd.totals,
            p.period_start::date,
            p.recent_views_start::date
        ) as total_block
    from params p
    cross join event_view_days evd
    cross join group_view_days gvd
)
-- Build each domain timeline and the page view metrics
select json_strip_nulls(json_build_object(
    'attendees', stats_timeline(
        (select jsonb_agg(to_jsonb(b)) from attendee_buckets b),
        false
    ),
    'cohosted_events', stats_timeline(
        (select jsonb_agg(to_jsonb(b)) from cohosted_event_buckets b),
        false
    ),
    'events', stats_timeline(
        (select jsonb_agg(to_jsonb(b)) from event_buckets b),
        false
    ),
    'members', stats_timeline(
        (select jsonb_agg(to_jsonb(b)) from member_buckets b),
        false
    ),
    'page_views', json_build_object(
        'events', pvb.events_block,
        'group', pvb.group_block,
        'total', pvb.total_block,
        'total_views', (pvb.total_block->>'total_views')::int
    )
))
from page_view_blocks pvb;
$$ language sql stable;
