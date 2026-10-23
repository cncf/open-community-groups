-- Parses the explore filters shared by the event and group search matchers:
-- community names resolved to ids, lowercased group categories and regions, and
-- the viewer location with its optional maximum distance. Absent or empty
-- community selections yield null; a non-empty selection that resolves to no
-- community yields an empty array so it matches nothing.
create or replace function parse_explore_filters(p_filters jsonb)
returns table (
    community_ids uuid[],
    group_category text[],
    max_distance real,
    region text[],
    user_location geography
) as $$
    select
        case
            when jsonb_array_length(coalesce(p_filters->'community', '[]'::jsonb)) > 0 then
                coalesce(
                    (
                        select array_agg(c.community_id)
                        from jsonb_array_elements_text(p_filters->'community') e
                        join community c on c.name = e
                    ),
                    array[]::uuid[]
                )
        end,
        (
            select array_agg(lower(e))
            from jsonb_array_elements_text(p_filters->'group_category') e
        ),
        case
            when p_filters ? 'latitude'
            and p_filters ? 'longitude'
            and p_filters ? 'distance' then
                (p_filters->>'distance')::real
        end,
        (
            select array_agg(lower(e))
            from jsonb_array_elements_text(p_filters->'region') e
        ),
        case
            when p_filters ? 'latitude'
            and p_filters ? 'longitude' then
                jsonb_geography_point(p_filters)
        end;
$$ language sql stable;
