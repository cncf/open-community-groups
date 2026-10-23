-- Deletes a sponsor from the group.
create or replace function delete_group_sponsor(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_group_sponsor_id uuid
)
returns void as $$
declare
    v_name text;
begin
    -- Lock the sponsor and snapshot its name for the audit row
    select gs.name
    into v_name
    from group_sponsor gs
    where gs.group_sponsor_id = p_group_sponsor_id
    and gs.group_id = p_group_id
    for update of gs;

    -- Reject sponsors outside the selected group
    if not found then
        raise exception 'sponsor not found' using errcode = 'OCG01';
    end if;

    -- Reject sponsors still used by any events
    if exists (
        select 1
        from event_sponsor
        where group_sponsor_id = p_group_sponsor_id
    ) then
        raise exception 'sponsor is used by one or more events' using errcode = 'OCG01';
    end if;

    -- Delete the sponsor
    delete from group_sponsor
    where group_sponsor_id = p_group_sponsor_id
    and group_id = p_group_id;

    -- Track the deleted sponsor
    perform insert_audit_log(
        'group_sponsor_deleted',
        p_actor_user_id,
        'group_sponsor',
        p_group_sponsor_id,
        p_group_id => p_group_id,
        p_details => jsonb_build_object('name', v_name)
    );
end;
$$ language plpgsql;
