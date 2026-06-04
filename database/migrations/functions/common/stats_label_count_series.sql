-- Builds an ordered label count series from labeled count rows.
create or replace function stats_label_count_series(p_counts jsonb)
returns json as $$
select coalesce(
    json_agg(json_build_array(label, count) order by label),
    '[]'::json
)
from (
    select
        count_row.label,
        count_row.count
    from jsonb_to_recordset(coalesce(p_counts, '[]'::jsonb)) as count_row(
        label text,
        count int
    )
) counts;
$$ language sql immutable;
