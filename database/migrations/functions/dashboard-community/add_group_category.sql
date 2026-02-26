-- Adds a new group category to a community.
create or replace function add_group_category(
    p_community_id uuid,
    p_group_category jsonb
)
returns uuid as $$
declare
    v_group_category_id uuid;
begin
    -- Insert the category record
    insert into group_category (
        community_id,
        name
    ) values (
        p_community_id,
        p_group_category->>'name'
    )
    returning group_category_id into v_group_category_id;

    return v_group_category_id;
exception when unique_violation then
    raise exception 'group category already exists';
end;
$$ language plpgsql;
