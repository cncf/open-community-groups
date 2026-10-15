-- Returns all-time UTM attribution statistics for an event.
--
-- Each dimension lists its top 8 stored values, the views without a value
-- and a remainder for the rest. Combinations are limited to the top 10 by
-- views, with a remainder for the rest.
create or replace function stats_event_utm(p_event event)
returns json as $$
with tagged_views as (
    select
        evu.day,
        evu.total::bigint as total,
        evu.utm_campaign,
        evu.utm_medium,
        evu.utm_source
    from event_views_utm evu
    where evu.event_id = p_event.event_id
),
dimension_values as (
    select
        dimension_value.dimension,
        dimension_value.value,
        sum(tv.total)::bigint as views
    from tagged_views tv
    cross join lateral (
        values
            ('campaign', tv.utm_campaign),
            ('medium', tv.utm_medium),
            ('source', tv.utm_source)
    ) as dimension_value(dimension, value)
    group by dimension_value.dimension, dimension_value.value
),
ranked_dimension_values as (
    select
        dv.dimension,
        row_number() over (
            partition by dv.dimension
            order by dv.views desc, dv.value
        ) as rank,
        dv.value,
        dv.views
    from dimension_values dv
    where dv.value <> ''
),
dimensions as (
    select
        dimension.name,
        json_build_object(
            'not_specified', coalesce((
                select dv.views
                from dimension_values dv
                where dv.dimension = dimension.name
                and dv.value = ''
            ), 0),
            'remainder_count', count(rdv.value) filter (where rdv.rank > 8),
            'remainder_views', coalesce(sum(rdv.views) filter (where rdv.rank > 8), 0)::bigint,
            'values', coalesce(
                json_agg(
                    json_build_object('value', rdv.value, 'views', rdv.views)
                    order by rdv.rank
                ) filter (where rdv.rank <= 8),
                '[]'::json
            )
        ) as stats
    from (values ('campaign'), ('medium'), ('source')) as dimension(name)
    left join ranked_dimension_values rdv on rdv.dimension = dimension.name
    group by dimension.name
),
ranked_combinations as (
    select
        min(tv.day) as first_day,
        max(tv.day) as last_day,
        row_number() over (
            order by sum(tv.total) desc, tv.utm_source, tv.utm_medium, tv.utm_campaign
        ) as rank,
        tv.utm_campaign,
        tv.utm_medium,
        tv.utm_source,
        sum(tv.total)::bigint as views
    from tagged_views tv
    group by tv.utm_campaign, tv.utm_medium, tv.utm_source
)
select json_build_object(
    'by_campaign', (select d.stats from dimensions d where d.name = 'campaign'),
    'by_medium', (select d.stats from dimensions d where d.name = 'medium'),
    'by_source', (select d.stats from dimensions d where d.name = 'source'),
    'combinations', coalesce((
        select json_agg(
            json_build_object(
                'first_day', to_char(rc.first_day, 'YYYY-MM-DD'),
                'last_day', to_char(rc.last_day, 'YYYY-MM-DD'),
                'views', rc.views,

                'utm_campaign', nullif(rc.utm_campaign, ''),
                'utm_medium', nullif(rc.utm_medium, ''),
                'utm_source', nullif(rc.utm_source, '')
            )
            order by rc.rank
        )
        from ranked_combinations rc
        where rc.rank <= 10
    ), '[]'::json),
    'combinations_remainder_views', coalesce((
        select sum(rc.views)
        from ranked_combinations rc
        where rc.rank > 10
    ), 0)::bigint,
    'combinations_total_count', (select count(*) from ranked_combinations),
    'tagged_views', coalesce((select sum(tv.total) from tagged_views tv), 0)::bigint
);
$$ language sql stable;
