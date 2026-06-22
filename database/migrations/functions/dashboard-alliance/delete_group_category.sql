-- Deletes a group category from a alliance when not in use.
create or replace function delete_group_category(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_group_category_id uuid
)
returns void as $$
declare
    v_groups_count bigint;
    v_name text;
begin
    -- Ensure the group category exists in the selected alliance, snapshotting
    -- its name so the audit row remains readable after deletion
    select gc.name
    into v_name
    from group_category gc
    where gc.alliance_id = p_alliance_id
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
    where gc.alliance_id = p_alliance_id
      and gc.group_category_id = p_group_category_id;

    -- Track the deletion
    perform insert_audit_log(
        'group_category_deleted',
        p_actor_user_id,
        'group_category',
        p_group_category_id,
        p_alliance_id,
        null,
        null,
        jsonb_build_object('name', v_name)
    );
end;
$$ language plpgsql;
