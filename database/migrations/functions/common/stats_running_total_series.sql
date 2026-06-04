-- Builds an ordered cumulative count series from timestamp bucket count rows.
create or replace function stats_running_total_series(p_counts jsonb)
returns json as $$
select coalesce(
    json_agg(json_build_array(ts, cumulative_total) order by ts),
    '[]'::json
)
from (
    select
        floor(extract(epoch from bucket_start) * 1000)::bigint as ts,
        sum(count) over (order by bucket_start)::int as cumulative_total
    from jsonb_to_recordset(coalesce(p_counts, '[]'::jsonb)) as count_row(
        bucket_start timestamptz,
        count int
    )
) totals;
$$ language sql immutable;
