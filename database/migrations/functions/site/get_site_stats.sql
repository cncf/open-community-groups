-- Returns site statistics as a JSON object.
--
-- The function computes statistics for alliance activity, jobs, and landscape
-- entries. Each domain includes the following stat types:
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
        gm.user_id,

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
        e.event_kind_id,
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
jobs as (
    select
        jj.expires_at,
        jj.job_id,
        jj.created_at,
        timezone(
            'UTC',
            date_trunc('month', jj.created_at at time zone 'UTC')
        ) as created_month
    from jobs_job jj
    where jj.published = true
),
landscape_startups as (
    select
        le.created_at,
        timezone(
            'UTC',
            date_trunc('month', le.created_at at time zone 'UTC')
        ) as created_month
    from landscape_entry le
    join alliance a on a.alliance_id = le.alliance_id
    where a.active = true
      and le.published = true
      and le.kind = 'startup'
),
landscape_open_source as (
    select
        le.created_at,
        timezone(
            'UTC',
            date_trunc('month', le.created_at at time zone 'UTC')
        ) as created_month
    from landscape_entry le
    join alliance a on a.alliance_id = le.alliance_id
    where a.active = true
      and le.published = true
      and le.kind = 'github_project'
),
mentorship_requests as (
    select
        mr.created_at,
        mr.mentor_user_id,
        mr.mentorship_request_id,
        timezone(
            'UTC',
            date_trunc('month', mr.created_at at time zone 'UTC')
        ) as created_month
    from mentorship_request mr
),
mentorship_group_requests as (
    select distinct
        mr.mentorship_request_id,
        fg.group_id,
        g.name as group_name
    from mentorship_requests mr
    join group_member gm on gm.user_id = mr.mentor_user_id
    join filtered_groups fg on fg.group_id = gm.group_id
    join "group" g on g.group_id = fg.group_id
),
job_applications as (
    select ja.created_at, ja.job_id, ja.applicant_user_id
    from jobs_application ja
    join jobs_job jj on jj.job_id = ja.job_id
),
active_member_user_ids as (
    select distinct m.user_id
    from members m
    where m.created_at >= current_timestamp - interval '90 days'

    union

    select distinct ea.user_id
    from event_attendee ea
    join events e on e.event_id = ea.event_id
    where ea.status = 'confirmed'
      and ea.created_at >= current_timestamp - interval '90 days'

    union

    select distinct ja.applicant_user_id
    from job_applications ja
    where ja.created_at >= current_timestamp - interval '90 days'
),
repeat_attendees as (
    select ea.user_id
    from event_attendee ea
    join events e on e.event_id = ea.event_id
    where ea.status = 'confirmed'
    group by ea.user_id
    having count(distinct ea.event_id) >= 2
),
linkedin_connected_members as (
    select distinct m.user_id
    from members m
    join "user" u on u.user_id = m.user_id
    where coalesce(u.provider ? 'linkedin', false)
       or nullif(u.linkedin_url, '') is not null
),
event_kind_counts as (
    select coalesce(ek.display_name, e.event_kind_id) as label, count(*)::int as count
    from events e
    join event_kind ek on ek.event_kind_id = e.event_kind_id
    group by coalesce(ek.display_name, e.event_kind_id)
),
event_category_counts as (
    select ec.name as label, count(*)::int as count
    from events e
    join event_category ec on ec.event_category_id = e.event_category_id
    group by ec.name
),
landscape_category_counts as (
    select coalesce(nullif(le.category, ''), 'Uncategorized') as label, count(*)::int as count
    from landscape_entry le
    join alliance a on a.alliance_id = le.alliance_id
    where a.active = true
      and le.published = true
    group by coalesce(nullif(le.category, ''), 'Uncategorized')
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

    union all

    select
        'jobs' as domain,
        j.created_month as bucket_start,
        count(*)::int as count
    from jobs j
    join params p on j.created_at >= p.period_start
    group by j.created_month

    union all

    select
        'landscape_startups' as domain,
        ls.created_month as bucket_start,
        count(*)::int as count
    from landscape_startups ls
    join params p on ls.created_at >= p.period_start
    group by ls.created_month

    union all

    select
        'landscape_open_source' as domain,
        los.created_month as bucket_start,
        count(*)::int as count
    from landscape_open_source los
    join params p on los.created_at >= p.period_start
    group by los.created_month
),
domain_monthly_counts as (
    select
        domain,
        to_char(bucket_start, 'YYYY-MM') as label,
        count
    from domain_running_total_counts
)
select json_strip_nulls(json_build_object(
    'summary', json_build_object(
        'active_members', (select count(*)::int from active_member_user_ids),
        'upcoming_events', (
            select count(*)::int
            from events e
            where e.starts_at >= current_timestamp
        ),
        'active_jobs', (
            select count(*)::int
            from jobs j
            where j.expires_at > current_timestamp
        ),
        'job_interests', (select count(*)::int from job_applications),
        'landscape_entries', (
            (select count(*)::int from landscape_startups)
            + (select count(*)::int from landscape_open_source)
        ),
        'avg_attendees_per_event', coalesce((
            select round(count(a.event_id)::numeric / nullif(count(distinct e.event_id), 0), 1)
            from events e
            left join attendees a on a.event_id = e.event_id
        ), 0)
    ),
    'engagement', json_build_object(
        'repeat_attendees', (select count(*)::int from repeat_attendees),
        'linkedin_connected_members', (select count(*)::int from linkedin_connected_members),
        'members_per_group_avg', coalesce((
            select round(count(m.user_id)::numeric / nullif(count(distinct fg.group_id), 0), 1)
            from filtered_groups fg
            left join members m on m.group_id = fg.group_id
        ), 0),
        'events_per_group_avg', coalesce((
            select round(count(e.event_id)::numeric / nullif(count(distinct fg.group_id), 0), 1)
            from filtered_groups fg
            left join events e on e.group_id = fg.group_id
        ), 0)
    ),
    'event_breakdown', json_build_object(
        'by_kind', coalesce((
            select json_agg(json_build_array(label, count) order by count desc, label)
            from event_kind_counts
        ), '[]'::json),
        'by_category', coalesce((
            select json_agg(json_build_array(label, count) order by count desc, label)
            from event_category_counts
        ), '[]'::json)
    ),
    'jobs_overview', json_build_object(
        'active', (
            select count(*)::int
            from jobs j
            where j.expires_at > current_timestamp
        ),
        'expired', (
            select count(*)::int
            from jobs j
            where j.expires_at <= current_timestamp
        ),
        'interests', (select count(*)::int from job_applications),
        'avg_interests_per_job', coalesce((
            select round(count(ja.job_id)::numeric / nullif(count(distinct j.job_id), 0), 1)
            from jobs j
            left join job_applications ja on ja.job_id = j.job_id
        ), 0)
    ),
    'mentorship_overview', json_build_object(
        'requests', (select count(*)::int from mentorship_requests),
        'requests_per_group_avg', coalesce((
            select round(count(mgr.mentorship_request_id)::numeric / nullif(count(distinct fg.group_id), 0), 1)
            from filtered_groups fg
            left join mentorship_group_requests mgr on mgr.group_id = fg.group_id
        ), 0),
        'by_group', coalesce((
            select json_agg(json_build_array(group_name, request_count) order by request_count desc, group_name)
            from (
                select
                    group_name,
                    count(*)::int as request_count
                from mentorship_group_requests
                group by group_name
                order by request_count desc, group_name
                limit 12
            ) counts
        ), '[]'::json)
    ),
    'landscape_overview', json_build_object(
        'entries', (
            (select count(*)::int from landscape_startups)
            + (select count(*)::int from landscape_open_source)
        ),
        'by_category', coalesce((
            select json_agg(json_build_array(label, count) order by count desc, label)
            from landscape_category_counts
        ), '[]'::json)
    ),
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
    ),
    'jobs', json_build_object(
        'per_month', stats_label_count_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_monthly_counts counts
            where domain = 'jobs'
        )),
        'running_total', stats_running_total_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_running_total_counts counts
            where domain = 'jobs'
        )),
        'total', (select count(*)::int from jobs)
    ),
    'landscape_startups', json_build_object(
        'per_month', stats_label_count_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_monthly_counts counts
            where domain = 'landscape_startups'
        )),
        'running_total', stats_running_total_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_running_total_counts counts
            where domain = 'landscape_startups'
        )),
        'total', (select count(*)::int from landscape_startups)
    ),
    'landscape_open_source', json_build_object(
        'per_month', stats_label_count_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_monthly_counts counts
            where domain = 'landscape_open_source'
        )),
        'running_total', stats_running_total_series((
            select jsonb_agg(to_jsonb(counts))
            from domain_running_total_counts counts
            where domain = 'landscape_open_source'
        )),
        'total', (select count(*)::int from landscape_open_source)
    )
));
$$ language sql;
