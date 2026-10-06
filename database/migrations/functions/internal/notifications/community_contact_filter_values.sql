-- Parses community contact filters into the values each filter selects.
-- Empty or missing filter lists produce empty arrays, which callers treat as
-- matching every value. Callers validate the filters with
-- validate_community_contact_filters first.
create or replace function community_contact_filter_values(
    p_filters jsonb
)
returns table (
    group_category_ids uuid[],
    include_no_region boolean,
    region_ids uuid[],
    roles text[]
) as $$
    select
        array(
            select value::uuid
            from jsonb_array_elements_text(coalesce(p_filters->'group_category_ids', '[]'))
        ) as group_category_ids,
        coalesce(p_filters->'regions', '[]') ? 'none' as include_no_region,
        array(
            select value::uuid
            from jsonb_array_elements_text(coalesce(p_filters->'regions', '[]'))
            where value <> 'none'
        ) as region_ids,
        array(
            select value
            from jsonb_array_elements_text(coalesce(p_filters->'roles', '[]'))
        ) as roles;
$$ language sql immutable;
