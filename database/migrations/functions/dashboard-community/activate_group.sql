-- activate_group sets active=true for an existing, non-deleted group.
create or replace function activate_group(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid
)
returns void as $$
begin
    -- Lock the target group before mutating it
    perform lock_active_group(p_community_id, p_group_id);

    -- Activate the target group
    update "group" set
        active = true
    where group_id = p_group_id;

    -- Track the activation
    perform insert_audit_log(
        'group_activated',
        p_actor_user_id,
        'group',
        p_group_id,
        p_community_id,
        p_group_id
    );
end;
$$ language plpgsql;
