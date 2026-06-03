-- Builds ordered cumulative count series grouped by name.
create or replace function stats_running_total_series_by_name(p_counts jsonb)
returns json as $$
with named_counts as (
    select
        series_name,
        jsonb_agg(to_jsonb(count_row)) as counts
    from jsonb_to_recordset(coalesce(p_counts, '[]'::jsonb)) as count_row(
        series_name text,
        bucket_start timestamptz,
        count int
    )
    group by series_name
)
select coalesce(
    json_object_agg(
        series_name,
        stats_running_total_series(counts)
        order by series_name
    ),
    '{}'::json
)
from named_counts;
$$ language sql immutable;
