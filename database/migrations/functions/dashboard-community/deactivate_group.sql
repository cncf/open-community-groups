-- deactivate_group sets active=false without marking as deleted.
create or replace function deactivate_group(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid
)
returns void as $$
begin
    -- Deactivate the target group
    update "group" set
        active = false
    where group_id = p_group_id
    and community_id = p_community_id
    and deleted = false;

    -- Ensure the target group exists and is active
    if not found then
        raise exception 'group not found or inactive';
    end if;

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
