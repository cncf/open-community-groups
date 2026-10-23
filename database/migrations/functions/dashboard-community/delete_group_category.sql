-- Deletes a group category from a community when not in use.
create or replace function delete_group_category(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_category_id uuid
)
returns void as $$
declare
    v_name text;
begin
    -- Lock the category and snapshot its name for the audit row
    select gc.name
    into v_name
    from group_category gc
    where gc.community_id = p_community_id
      and gc.group_category_id = p_group_category_id
    for update of gc;

    -- Reject categories outside the selected community
    if not found then
        raise exception 'group category not found' using errcode = 'OCG01';
    end if;

    -- Reject categories still used by any groups, including deleted ones
    if exists (
        select 1
        from "group" g
        where g.group_category_id = p_group_category_id
    ) then
        raise exception 'cannot delete group category in use by groups' using errcode = 'OCG01';
    end if;

    -- Delete the category record
    delete from group_category gc
    where gc.community_id = p_community_id
      and gc.group_category_id = p_group_category_id;

    -- Track the deletion
    perform insert_audit_log(
        'group_category_deleted',
        p_actor_user_id,
        'group_category',
        p_group_category_id,
        p_community_id,
        null,
        null,
        jsonb_build_object('name', v_name)
    );
end;
$$ language plpgsql;
