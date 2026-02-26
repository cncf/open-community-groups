-- Updates a group category in a community.
create or replace function update_group_category(
    p_community_id uuid,
    p_group_category_id uuid,
    p_group_category jsonb
)
returns void as $$
begin
    -- Ensure the target category exists in the selected community
    perform 1
    from group_category gc
    where gc.community_id = p_community_id
      and gc.group_category_id = p_group_category_id;

    if not found then
        raise exception 'group category not found';
    end if;

    -- Update the category record
    update group_category set
        name = p_group_category->>'name'
    where community_id = p_community_id
      and group_category_id = p_group_category_id;
exception when unique_violation then
    raise exception 'group category already exists';
end;
$$ language plpgsql;
