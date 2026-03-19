-- Leave an event as an attendee.
create or replace function leave_event(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
) returns json as $$
declare
    v_capacity int;
    v_promoted_user_ids json := '[]'::json;
begin
    -- Check if event exists in the community, is active and can be left
    select e.capacity
    into v_capacity
    from event e
    join "group" g on g.group_id = e.group_id
    where e.event_id = p_event_id
    and g.community_id = p_community_id
    and g.active = true
    and e.deleted = false
    and e.published = true
    and e.canceled = false
    and (
        coalesce(e.ends_at, e.starts_at) is null
        or coalesce(e.ends_at, e.starts_at) >= current_timestamp
    )
    for update of e;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Remove the user from confirmed attendees first
    delete from event_attendee
    where event_id = p_event_id
    and user_id = p_user_id;

    if found then
        -- Promote the next waitlisted user when a confirmed attendee frees a seat
        select promote_event_waitlist(
            p_event_id,
            case when v_capacity is null then null else 1 end
        )
        into v_promoted_user_ids;

        return json_build_object(
            'left_status', 'attendee',
            'promoted_user_ids', v_promoted_user_ids
        );
    end if;

    -- Otherwise remove the user from the waiting list
    delete from event_waitlist
    where event_id = p_event_id
    and user_id = p_user_id;

    if found then
        return json_build_object(
            'left_status', 'waitlisted',
            'promoted_user_ids', '[]'::json
        );
    end if;

    raise exception 'user is not attending or waitlisted for this event';
end;
$$ language plpgsql;
