-- Projects a group category as the JSON read by the server group models.
create or replace function group_category_json(p_group_category group_category)
returns json as $$
    select json_build_object(
        'group_category_id', p_group_category.group_category_id,
        'name', p_group_category.name,
        'normalized_name', p_group_category.normalized_name,
        'order', p_group_category."order"
    );
$$ language sql stable;
