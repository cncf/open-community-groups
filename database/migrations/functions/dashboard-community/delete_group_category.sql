-- Deletes a group category from a community when not in use.
create or replace function delete_group_category(
    p_community_id uuid,
    p_group_category_id uuid
)
returns void as $$
declare
    v_groups_count bigint;
begin
    -- Ensure the group category exists in the selected community
    perform 1
    from group_category gc
    where gc.community_id = p_community_id
      and gc.group_category_id = p_group_category_id;

    if not found then
        raise exception 'group category not found';
    end if;

    -- Block deletion when groups still reference this category
    select count(*)
    into v_groups_count
    from "group" g
    where g.group_category_id = p_group_category_id;

    if v_groups_count > 0 then
        raise exception 'cannot delete group category in use by groups';
    end if;

    -- Delete the category record
    delete from group_category gc
    where gc.community_id = p_community_id
      and gc.group_category_id = p_group_category_id;
end;
$$ language plpgsql;
