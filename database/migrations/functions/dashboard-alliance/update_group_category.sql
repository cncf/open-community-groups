-- Updates a group category in a alliance.
create or replace function update_group_category(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_group_category_id uuid,
    p_group_category jsonb
)
returns void as $$
begin
    -- Ensure the target category exists in the selected alliance
    perform 1
    from group_category gc
    where gc.alliance_id = p_alliance_id
      and gc.group_category_id = p_group_category_id;

    if not found then
        raise exception 'group category not found';
    end if;

    -- Update the category record
    update group_category set
        name = p_group_category->>'name'
    where alliance_id = p_alliance_id
      and group_category_id = p_group_category_id;

    -- Track the updated category
    perform insert_audit_log(
        'group_category_updated',
        p_actor_user_id,
        'group_category',
        p_group_category_id,
        p_alliance_id
    );
exception when unique_violation then
    raise exception 'group category already exists';
end;
$$ language plpgsql;
