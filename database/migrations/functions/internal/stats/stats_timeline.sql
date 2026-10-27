-- Builds the per_month, running_total and total timeline of a stats domain.
--
-- Input rows are monthly buckets {bucket_start timestamptz (null for undated
-- entities), count int, in_period boolean}. total counts every row. per_month
-- counts in-period rows, labeled 'YYYY-MM' from bucket_start at UTC.
-- running_total accumulates dated rows, or only in-period rows when
-- p_running_total_from_period.
--
-- Running-total rows are regrouped by bucket_start because a month that
-- straddles the period start arrives as two rows. The function is stable
-- because to_char is stable.
create or replace function stats_timeline(
    p_buckets jsonb,
    p_running_total_from_period boolean
)
returns json as $$
-- Expand the monthly bucket rows
with buckets as (
    select
        b.bucket_start,
        b.count,
        b.in_period
    from jsonb_to_recordset(coalesce(p_buckets, '[]'::jsonb)) as b(
        bucket_start timestamptz,
        count int,
        in_period boolean
    )
)
-- Build the domain timeline
select json_build_object(
    'per_month', stats_label_count_series((
        select jsonb_agg(jsonb_build_object('count', m.count, 'label', m.label))
        from (
            select
                to_char(b.bucket_start at time zone 'UTC', 'YYYY-MM') as label,
                sum(b.count)::int as count
            from buckets b
            where b.in_period
            group by 1
        ) m
    )),
    'running_total', stats_running_total_series((
        select jsonb_agg(jsonb_build_object('bucket_start', r.bucket_start, 'count', r.count))
        from (
            select
                b.bucket_start,
                sum(b.count)::int as count
            from buckets b
            where b.bucket_start is not null
            and (b.in_period or not p_running_total_from_period)
            group by b.bucket_start
        ) r
    )),
    'total', (select coalesce(sum(b.count), 0)::int from buckets b)
);
$$ language sql stable;
