-- Returns check-in arrivals of an event in aligned time bins.
--
-- Bins are 15 minutes wide and aligned to the hour of the event start, or of
-- the first check-in for undated events; they widen to 60 minutes when the
-- span exceeds 3 days. The span runs from the earliest check-in, or one hour
-- before the start, to the latest check-in, bounded to six hours around the
-- event. Check-ins more than six hours before the start or after the end are
-- counted separately instead of being binned.
create or replace function stats_event_check_ins(p_event event)
returns json as $$
with check_ins as (
    select ea.checked_in_at
    from event_attendee ea
    where ea.event_id = p_event.event_id
    and ea.status = 'confirmed'
    and ea.checked_in = true
    and ea.checked_in_at is not null
),
bounded_check_ins as (
    select ci.checked_in_at
    from check_ins ci
    where (
        p_event.starts_at is null
        or ci.checked_in_at >= p_event.starts_at - interval '6 hours'
    )
    and (
        event_effective_ends_at(p_event) is null
        or ci.checked_in_at <= event_effective_ends_at(p_event) + interval '6 hours'
    )
),
check_in_span as (
    select
        greatest(
            least(min(ci.checked_in_at), p_event.starts_at - interval '1 hour'),
            p_event.starts_at - interval '6 hours'
        ) as lower_at,
        date_trunc('hour', coalesce(p_event.starts_at, min(ci.checked_in_at)), 'UTC') as origin,
        least(
            max(ci.checked_in_at),
            event_effective_ends_at(p_event) + interval '6 hours'
        ) as upper_at
    from check_ins ci
    having count(*) > 0
),
bin_layout as (
    select
        date_bin(layout.width, cis.lower_at, cis.origin) as first_bin_at,
        date_bin(layout.width, greatest(cis.upper_at, cis.lower_at), cis.origin) as last_bin_at,
        cis.origin,
        layout.width
    from check_in_span cis
    cross join lateral (
        select case
            when greatest(cis.upper_at, cis.lower_at) - cis.lower_at > interval '3 days'
                then interval '60 minutes'
            else interval '15 minutes'
        end as width
    ) layout
),
binned_check_ins as (
    select
        date_bin(bl.width, ci.checked_in_at, bl.origin) as bin_at,
        count(*)::bigint as total
    from bounded_check_ins ci
    cross join bin_layout bl
    group by 1
),
bins as (
    select
        series_bin.bin_at,
        coalesce(bci.total, 0) as total
    from bin_layout bl
    cross join generate_series(bl.first_bin_at, bl.last_bin_at, bl.width) as series_bin(bin_at)
    left join binned_check_ins bci on bci.bin_at = series_bin.bin_at
)
select json_build_object(
    'bin_minutes', coalesce((
        select (extract(epoch from bl.width) / 60)::int
        from bin_layout bl
    ), 15),
    'bins', coalesce((
        select json_agg(
            json_build_array(floor(extract(epoch from b.bin_at) * 1000)::bigint, b.total)
            order by b.bin_at
        )
        from bins b
    ), '[]'::json),
    'outside_range', (
        (select count(*) from check_ins) - (select count(*) from bounded_check_ins)
    )
);
$$ language sql stable;
