-- deactivate_group sets active=false without marking as deleted.
create or replace function deactivate_group(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid
)
returns void as $$
begin
    -- Lock the target group before mutating it
    perform lock_active_group(p_community_id, p_group_id);

    -- Deactivate the target group
    update "group" set
        active = false
    where group_id = p_group_id;

    -- Track the deactivation
    perform insert_audit_log(
        'group_deactivated',
        p_actor_user_id,
        'group',
        p_group_id,
        p_community_id,
        p_group_id
    );
end;
$$ language plpgsql;
