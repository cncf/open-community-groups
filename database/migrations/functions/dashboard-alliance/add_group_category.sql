-- Adds a new group category to a alliance.
create or replace function add_group_category(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_group_category jsonb
)
returns uuid as $$
declare
    v_group_category_id uuid;
begin
    -- Insert the category record
    insert into group_category (
        alliance_id,
        name
    ) values (
        p_alliance_id,
        p_group_category->>'name'
    )
    returning group_category_id into v_group_category_id;

    -- Track the created category
    perform insert_audit_log(
        'group_category_added',
        p_actor_user_id,
        'group_category',
        v_group_category_id,
        p_alliance_id
    );

    return v_group_category_id;
exception when unique_violation then
    raise exception 'group category already exists';
end;
$$ language plpgsql;
