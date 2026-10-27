-- Returns lifecycle traffic and registration series for an event.
--
-- Views and registrations are bucketed per UTC day between p_start_day and
-- p_end_day. Series are empty when the bounds are missing or inverted, while
-- the all-time totals are always reported.
create or replace function stats_event_traffic(
    p_event event,
    p_start_day date,
    p_end_day date
)
returns json as $$
-- Keep the requested day range only when its bounds are ordered
with bounds as (
    select
        p_end_day as end_day,
        p_start_day as start_day
    where p_start_day <= p_end_day
),
-- Total the event views of each day
daily_views as (
    select
        ev.day,
        sum(ev.total)::bigint as total
    from event_views ev
    where ev.event_id = p_event.event_id
    group by ev.day
),
-- Load the event views attributed to a UTM source
tagged_views as (
    select
        evu.day,
        evu.total::bigint as total,
        evu.utm_source
    from event_views_utm evu
    where evu.event_id = p_event.event_id
),
-- Total the tagged views of each day
daily_tagged_views as (
    select
        tv.day,
        sum(tv.total)::bigint as total
    from tagged_views tv
    group by tv.day
),
-- Derive the untagged views of each day
untagged_counts as (
    select
        coalesce(dv.day, dtv.day) as day,
        coalesce(dv.total, 0) - coalesce(dtv.total, 0) as total
    from daily_views dv
    full join daily_tagged_views dtv on dtv.day = dv.day
),
-- Keep the tagged views inside the day range
range_tagged_views as (
    select
        tv.day,
        tv.total,
        tv.utm_source
    from tagged_views tv
    join bounds b on tv.day between b.start_day and b.end_day
),
-- Rank the named sources by their views inside the day range
ranked_sources as (
    select
        rtv.utm_source,
        row_number() over (order by sum(rtv.total) desc, rtv.utm_source) as rank
    from range_tagged_views rtv
    where rtv.utm_source <> ''
    group by rtv.utm_source
),
-- Classify the tagged views into top sources, other sources and no source
classified_tagged_views as (
    select
        case
            -- Group views tagged without a source
            when rtv.utm_source = '' then 'no-source'
            -- Keep each of the top three sources apart
            when rs.rank <= 3 then 'source'
            -- Group the remaining sources
            else 'other-sources'
        end as kind,
        case
            -- Place views without a source after the other sources
            when rtv.utm_source = '' then 5
            -- Place the top three sources by rank
            when rs.rank <= 3 then rs.rank
            -- Place the remaining sources after the top three
            else 4
        end as position,
        case
            -- Name only the top three sources
            when rs.rank <= 3 then rtv.utm_source
        end as source,
        rtv.day,
        rtv.total
    from range_tagged_views rtv
    left join ranked_sources rs on rs.utm_source = rtv.utm_source
),
-- Collect the daily counts of each tagged series with views
tagged_series_counts as (
    select
        ctv.kind,
        ctv.position,
        ctv.source,
        jsonb_agg(jsonb_build_object('count', ctv.total, 'day', ctv.day)) as counts
    from classified_tagged_views ctv
    group by ctv.kind, ctv.position, ctv.source
    having sum(ctv.total) > 0
),
-- Build the daily series of each tagged group and of the untagged views
views_series as (
    -- Fill the day range of each tagged series
    select
        tsc.kind,
        tsc.position,
        tsc.source,
        stats_day_count_series(b.start_day, b.end_day, tsc.counts) as series
    from tagged_series_counts tsc
    cross join bounds b

    union all

    -- Fill the day range of the untagged views
    select
        'untagged' as kind,
        6 as position,
        null as source,
        stats_day_count_series(b.start_day, b.end_day, (
            select jsonb_agg(jsonb_build_object('count', uc.total, 'day', uc.day))
            from untagged_counts uc
            where uc.day between b.start_day and b.end_day
        )) as series
    from bounds b
),
-- Date each confirmed registration and tag it with its seat purchase tier
registrations as (
    select
        (ea.created_at at time zone 'UTC')::date as day,
        ett.event_ticket_type_id,
        ett."order",
        ett.title
    from event_attendee ea
    left join event_seat_purchases(p_event.event_id) sp on sp.user_id = ea.user_id
    left join event_ticket_type ett on ett.event_ticket_type_id = sp.event_ticket_type_id
    where ea.event_id = p_event.event_id
    and ea.status = 'confirmed'
),
-- Count the registrations of each day and tier inside the day range
registration_day_counts as (
    select
        r.day,
        r.event_ticket_type_id,
        r."order",
        r.title,
        count(*)::bigint as total
    from registrations r
    join bounds b on r.day between b.start_day and b.end_day
    group by r.day, r.event_ticket_type_id, r."order", r.title
),
-- Fill the day range of each tier's registrations
registration_series as (
    select
        case
            -- Report registrations without a seat purchase tier as unknown
            when rdc.event_ticket_type_id is null then 'unknown'
            -- Report registrations attributed to a tier
            else 'ticket-type'
        end as kind,
        rdc.event_ticket_type_id,
        rdc."order",
        rdc.title,
        stats_day_count_series(
            b.start_day,
            b.end_day,
            jsonb_agg(jsonb_build_object('count', rdc.total, 'day', rdc.day))
        ) as series
    from registration_day_counts rdc
    cross join bounds b
    group by rdc.event_ticket_type_id, rdc."order", rdc.title, b.start_day, b.end_day
),
-- Count the registrations before the day range
registrations_baseline as (
    select count(*)::bigint as total
    from registrations r
    join bounds b on r.day < b.start_day
),
-- Accumulate the registrations of each day of the range
registrations_running_total as (
    select
        series_day.day,
        (
            (select rb.total from registrations_baseline rb)
            + sum(count(r.day)) over (order by series_day.day)
        )::bigint as total
    from bounds b
    cross join generate_series(
        b.start_day::timestamp,
        b.end_day::timestamp,
        interval '1 day'
    ) as series_day(day)
    left join registrations r on r.day = series_day.day::date
    group by series_day.day
)
-- Build the traffic payload
select json_build_object(
    'attribution_consistent', (
        coalesce((select sum(dtv.total) from daily_tagged_views dtv), 0)
            <= coalesce((select sum(dv.total) from daily_views dv), 0)
        and not exists (
            select 1
            from untagged_counts uc
            join bounds b on uc.day between b.start_day and b.end_day
            where uc.total < 0
        )
    ),
    'registrations_baseline', (select rb.total from registrations_baseline rb),
    'registrations_by_ticket_type_per_day', coalesce((
        select json_agg(
            json_build_object(
                'kind', rs.kind,
                'series', rs.series,

                'event_ticket_type_id', rs.event_ticket_type_id,
                'order', rs."order",
                'title', rs.title
            )
            order by
                rs.event_ticket_type_id is null,
                rs."order",
                rs.title,
                rs.event_ticket_type_id
        )
        from registration_series rs
    ), '[]'::json),
    'registrations_running_total', coalesce((
        select json_agg(
            json_build_array(to_char(rrt.day, 'YYYY-MM-DD'), rrt.total)
            order by rrt.day
        )
        from registrations_running_total rrt
    ), '[]'::json),
    'views_after_end', coalesce((
        select sum(dv.total)
        from daily_views dv
        join bounds b on dv.day > b.end_day
    ), 0)::bigint,
    'views_before_start', coalesce((
        select sum(dv.total)
        from daily_views dv
        join bounds b on dv.day < b.start_day
    ), 0)::bigint,
    'views_by_source_per_day', coalesce((
        select json_agg(
            json_build_object(
                'kind', vs.kind,
                'series', vs.series,

                'source', vs.source
            )
            order by vs.position, vs.source
        )
        from views_series vs
    ), '[]'::json),
    'views_total', coalesce((select sum(dv.total) from daily_views dv), 0)::bigint
);
$$ language sql stable;
