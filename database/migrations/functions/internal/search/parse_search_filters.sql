-- Parses the pagination, text, date and sort keys shared by search and list
-- functions from their jsonb filters. Missing keys yield nulls so callers
-- apply their own defaults; pagination values are clamped to be non-negative
-- and the free-text query is trimmed, exposed as an ILIKE pattern and as a
-- prefix-matching tsquery. Function-specific keys stay in the caller.
create or replace function parse_search_filters(p_filters jsonb)
returns table (
    date_from date,
    date_to date,
    ilike_pattern text,
    limit_value int,
    offset_value int,
    sort text,
    ts_query text,
    tsquery tsquery
) as $$
    with parsed as (
        select
            nullif(p_filters->>'date_from', '')::date as date_from,
            nullif(p_filters->>'date_to', '')::date as date_to,
            case
                when p_filters ? 'limit' then greatest((p_filters->>'limit')::int, 0)
            end as limit_value,
            case
                when p_filters ? 'offset' then greatest((p_filters->>'offset')::int, 0)
            end as offset_value,
            lower(nullif(btrim(p_filters->>'sort'), '')) as sort,
            nullif(btrim(p_filters->>'ts_query'), '') as ts_query
    )
    select
        date_from,
        date_to,
        '%' || escape_ilike_pattern(ts_query) || '%',
        limit_value,
        offset_value,
        sort,
        ts_query,
        prefix_tsquery('simple', ts_query)
    from parsed;
$$ language sql stable;
