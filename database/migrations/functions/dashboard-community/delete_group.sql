-- delete_group performs a soft delete by setting deleted=true and deleted_at timestamp.
create or replace function delete_group(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid
)
returns void as $$
begin
    -- Soft-delete the target group
    update "group" set
        active = false,
        deleted = true,
        deleted_at = current_timestamp
    where group_id = p_group_id
    and community_id = p_community_id
    and deleted = false;

    -- Ensure the target group exists and is active
    if not found then
        raise exception 'group not found or inactive';
    end if;

    -- Track the deletion
    perform insert_audit_log(
        'group_deleted',
        p_actor_user_id,
        'group',
        p_group_id,
        p_community_id,
        p_group_id
    );
end;
$$ language plpgsql;
