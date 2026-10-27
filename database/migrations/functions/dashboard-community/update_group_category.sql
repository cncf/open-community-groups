-- Updates a group category in a community.
create or replace function update_group_category(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_category_id uuid,
    p_group_category jsonb
)
returns void as $$
begin
    -- Update the category record
    update group_category set
        name = p_group_category->>'name'
    where community_id = p_community_id
      and group_category_id = p_group_category_id;

    -- Reject targets outside the selected community
    if not found then
        raise exception 'group category not found' using errcode = 'OCG01';
    end if;

    -- Track the updated category
    perform insert_audit_log(
        'group_category_updated',
        p_actor_user_id,
        'group_category',
        p_group_category_id,
        p_community_id
    );
exception
    -- Translate duplicate category names
    when unique_violation then
        raise exception 'group category already exists' using errcode = 'OCG01';
end;
$$ language plpgsql;
