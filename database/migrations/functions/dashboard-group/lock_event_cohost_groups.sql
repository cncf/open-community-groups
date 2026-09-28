-- Locks an owner group and every requested co-host group in stable order.
create or replace function lock_event_cohost_groups(
    p_group_id uuid,
    p_cohost_group_ids uuid[]
)
returns void as $$
begin
    -- Lock every participating group in UUID order to prevent invite cycles from deadlocking
    perform 1
    from "group" g
    where g.group_id = any(array_append(coalesce(p_cohost_group_ids, '{}'::uuid[]), p_group_id))
    order by g.group_id
    for update of g;
end;
$$ language plpgsql;
