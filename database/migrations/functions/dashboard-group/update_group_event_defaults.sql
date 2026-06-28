-- update_group_event_defaults stores or clears the default event payload for a group.
create or replace function update_group_event_defaults(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_defaults jsonb
)
returns void as $$
begin
    update "group"
    set event_defaults = nullif(p_event_defaults, 'null'::jsonb)
    where group_id = p_group_id
      and deleted = false;

    if not found then
        raise exception 'group not found';
    end if;

    perform insert_audit_log(
        'group_event_defaults_updated',
        p_actor_user_id,
        'group',
        p_group_id,
        null,
        p_group_id
    );
end;
$$ language plpgsql;
