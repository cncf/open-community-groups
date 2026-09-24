-- Closes open co-host invitations when an event is canceled or deleted.
create or replace function close_event_cohosts(
    p_actor_user_id uuid,
    p_event_id uuid,
    p_status text
)
returns void as $$
declare
    v_changed record;
    v_changed_count int := 0;
    v_owner_group_id uuid;
begin
    -- Validate the terminal transition target
    if p_status not in ('event-canceled', 'event-deleted') then
        raise exception 'invalid event co-host close status';
    end if;

    -- Resolve the owner group for audit scope and revision updates
    select group_id
    into v_owner_group_id
    from event
    where event_id = p_event_id;

    -- Reject callers that pass an unknown event
    if not found then
        raise exception 'event not found';
    end if;

    -- Close the co-host rows affected by the event transition
    for v_changed in
        select
            ec.group_id,
            ec.invitation_id,
            ec.event_cohost_status_id as from_status
        from event_cohost ec
        where ec.event_id = p_event_id
        and (
            (
                p_status = 'event-canceled'
                and ec.event_cohost_status_id in ('approved', 'pending')
            )
            or (
                p_status = 'event-deleted'
                and ec.event_cohost_status_id in ('approved', 'event-canceled', 'pending')
            )
        )
        order by ec.group_id
    loop
        -- Persist the terminal event-driven status
        update event_cohost
        set
            event_cohost_status_id = p_status,
            responded_at = current_timestamp,
            responded_by = p_actor_user_id,
            updated_at = current_timestamp
        where event_id = p_event_id
        and group_id = v_changed.group_id;

        -- Audit every changed owner/co-host pair
        perform insert_event_cohost_audit(
            'event_cohost_closed',
            p_actor_user_id,
            p_event_id,
            v_owner_group_id,
            v_changed.group_id,
            v_changed.invitation_id,
            v_changed.from_status,
            p_status
        );

        -- Count changed rows for the revision update
        v_changed_count := v_changed_count + 1;
    end loop;

    -- Advance the editor revision only when rows changed
    if v_changed_count > 0 then
        update event
        set cohosts_revision = cohosts_revision + 1
        where event_id = p_event_id;
    end if;
end;
$$ language plpgsql;
