-- Leave an event as an attendee.
create or replace function leave_event(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
) returns json as $$
declare
    v_capacity int;
    v_event_discount_code_id uuid;
    v_is_ticketed boolean;
    v_promoted_user_ids json := '[]'::json;
    v_purchase_amount_minor bigint;
    v_purchase_id uuid;
begin
    -- Check if event exists in the community, is active and can be left
    select
        e.capacity,
        exists(
            select 1
            from event_ticket_type ett
            where ett.event_id = e.event_id
        )
    into
        v_capacity,
        v_is_ticketed
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

    -- Paid attendees must request a refund instead of leaving the event
    select
        ep.amount_minor,
        ep.event_discount_code_id,
        ep.event_purchase_id
    into
        v_purchase_amount_minor,
        v_event_discount_code_id,
        v_purchase_id
    from event_purchase ep
    where ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and ep.status in ('completed', 'refund-requested')
    order by ep.created_at desc, ep.event_purchase_id desc
    limit 1;

    if v_purchase_amount_minor > 0 then
        raise exception 'paid attendees must request a refund instead of leaving the event';
    end if;

    -- Remove the user from confirmed attendees first
    delete from event_attendee
    where event_id = p_event_id
    and user_id = p_user_id;

    if found then
        -- If the user had a free ticket purchase, mark it as refunded and restore discount availability
        if v_purchase_id is not null then
            update event_purchase
            set
                refunded_at = current_timestamp,
                status = 'refunded',
                updated_at = current_timestamp
            where event_purchase_id = v_purchase_id;

            if v_event_discount_code_id is not null then
                perform release_event_discount_code_availability(v_event_discount_code_id);
            end if;
        end if;

        -- Promote the next waitlisted user when a confirmed attendee frees a seat
        if not v_is_ticketed then
            select promote_event_waitlist(
                p_event_id,
                case when v_capacity is null then null else 1 end
            )
            into v_promoted_user_ids;
        end if;

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
