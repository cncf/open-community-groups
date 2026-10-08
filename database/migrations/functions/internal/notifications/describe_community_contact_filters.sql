-- Describes community contact filters with readable names for audit details.
-- Empty or missing filter lists are described as "All". Callers validate the
-- filters with validate_community_contact_filters first.
create or replace function describe_community_contact_filters(
    p_community_id uuid,
    p_filters jsonb
)
returns jsonb as $$
    -- Build the readable names for each filter
    select jsonb_build_object(
        'group_categories', case
            when cardinality(f.group_category_ids) = 0 then to_jsonb('All'::text)
            else (
                select coalesce(jsonb_agg(gc.name order by gc."order" nulls last, gc.name), '[]')
                from group_category gc
                where gc.community_id = p_community_id
                and gc.group_category_id = any(f.group_category_ids)
            )
        end,
        'regions', case
            when cardinality(f.region_ids) = 0 and not f.include_no_region then to_jsonb('All'::text)
            else (
                select coalesce(jsonb_agg(r.name order by r."order" nulls last, r.name), '[]')
                from region r
                where r.community_id = p_community_id
                and r.region_id = any(f.region_ids)
            ) || case when f.include_no_region then '["No region"]'::jsonb else '[]'::jsonb end
        end,
        'roles', case
            when cardinality(f.roles) = 0 then to_jsonb('All'::text)
            else (
                select coalesce(
                    jsonb_agg(
                        gr.display_name
                        order by
                            array_position(
                                array['admin', 'events-manager', 'check-in-manager', 'viewer'],
                                gr.group_role_id
                            ) nulls last,
                            gr.display_name
                    ),
                    '[]'
                )
                from group_role gr
                where gr.group_role_id = any(f.roles)
            )
        end
    )
    from community_contact_filter_values(p_filters) f;
$$ language sql stable;
