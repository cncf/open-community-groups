-- Builds a dense daily count series between two days, filling missing days with zeros.
create or replace function stats_day_count_series(
    p_start_day date,
    p_end_day date,
    p_counts jsonb
)
returns json as $$
select coalesce(
    json_agg(
        json_build_array(to_char(series_day.day, 'YYYY-MM-DD'), coalesce(day_count.count, 0))
        order by series_day.day
    ),
    '[]'::json
)
from generate_series(
    p_start_day::timestamp,
    p_end_day::timestamp,
    interval '1 day'
) as series_day(day)
left join (
    select
        count_row.day,
        sum(count_row.count)::bigint as count
    from jsonb_to_recordset(coalesce(p_counts, '[]'::jsonb)) as count_row(
        day date,
        count bigint
    )
    group by count_row.day
) day_count on day_count.day = series_day.day::date;
$$ language sql stable;
