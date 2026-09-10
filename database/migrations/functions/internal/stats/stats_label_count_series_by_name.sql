-- Builds ordered label count series grouped by name.
create or replace function stats_label_count_series_by_name(p_counts jsonb)
returns json as $$
with named_counts as (
    select
        count_row.series_name,
        jsonb_agg(to_jsonb(count_row)) as counts
    from jsonb_to_recordset(coalesce(p_counts, '[]'::jsonb)) as count_row(
        series_name text,
        label text,
        count int
    )
    group by count_row.series_name
)
select coalesce(
    json_object_agg(
        series_name,
        stats_label_count_series(counts)
        order by series_name
    ),
    '{}'::json
)
from named_counts;
$$ language sql immutable;
