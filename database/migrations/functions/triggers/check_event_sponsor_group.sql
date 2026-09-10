-- Rejects event sponsors owned by a different group than the event.
create or replace function check_event_sponsor_group()
returns trigger as $$
declare
    v_event_group_id uuid;
    v_sponsor_group_id uuid;
begin
    -- Resolve the group that owns the event
    select group_id into v_event_group_id
    from event
    where event_id = new.event_id;

    -- Resolve the group that owns the sponsor
    select group_id into v_sponsor_group_id
    from group_sponsor
    where group_sponsor_id = new.group_sponsor_id;

    -- Reject sponsors from another group
    if v_sponsor_group_id is distinct from v_event_group_id then
        raise exception 'sponsor not found in group' using errcode = 'OCG01';
    end if;

    -- Return the validated sponsor row
    return new;
end;
$$ language plpgsql;
