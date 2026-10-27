-- Builds a page views block from daily view totals.
--
-- p_days and p_totals are parallel arrays of daily view totals. Rows of the
-- same day are summed, so callers may concatenate the arrays of several
-- scopes. total_views is all-time, per_day_views covers days on or after
-- p_recent_start, and per_month_views covers months of days on or after
-- p_period_start. Both series have the stats_label_count_series shape, built
-- here without nested function calls. Labels derive from the stored day, so
-- they do not depend on the session time zone. Typed arrays avoid a jsonb
-- round trip per day. The function is stable because to_char is stable.
create or replace function stats_page_views(
    p_days date[],
    p_totals int[],
    p_period_start date,
    p_recent_start date
)
returns json as $$
-- Build the page views block
select json_build_object(
    'per_day_views', coalesce((
        select json_agg(json_build_array(d.label, d.count) order by d.label)
        from (
            select
                to_char(v.day::timestamp, 'YYYY-MM-DD') as label,
                sum(v.total)::int as count
            from unnest(p_days, p_totals) as v(day, total)
            where v.day >= p_recent_start
            group by v.day
        ) d
    ), '[]'::json),
    'per_month_views', coalesce((
        select json_agg(json_build_array(m.label, m.count) order by m.label)
        from (
            select
                to_char(date_trunc('month', v.day::timestamp), 'YYYY-MM') as label,
                sum(v.total)::int as count
            from unnest(p_days, p_totals) as v(day, total)
            where v.day >= p_period_start
            group by date_trunc('month', v.day::timestamp)
        ) m
    ), '[]'::json),
    'total_views', coalesce((
        select sum(t.total)
        from unnest(p_totals) as t(total)
    ), 0)::int
);
$$ language sql stable;
