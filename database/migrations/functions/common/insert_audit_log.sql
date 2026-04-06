-- Inserts an audit log entry for a successful mutation.
create or replace function insert_audit_log(
    p_action text,
    p_actor_user_id uuid,
    p_resource_type text,
    p_resource_id uuid,
    p_community_id uuid default null,
    p_group_id uuid default null,
    p_event_id uuid default null,
    p_details jsonb default null
)
returns void as $$
declare
    v_actor_username text;
begin
    -- Snapshot the actor username so audit rows remain readable if user records change
    if p_actor_user_id is not null then
        select username
        into v_actor_username
        from "user"
        where user_id = p_actor_user_id;
    end if;

    -- Store the audit row
    insert into audit_log (
        action,
        actor_user_id,
        actor_username,
        community_id,
        details,
        event_id,
        group_id,
        resource_id,
        resource_type
    ) values (
        p_action,
        p_actor_user_id,
        v_actor_username,
        p_community_id,
        coalesce(p_details, '{}'::jsonb),
        p_event_id,
        p_group_id,
        p_resource_id,
        p_resource_type
    );
end;
$$ language plpgsql;
