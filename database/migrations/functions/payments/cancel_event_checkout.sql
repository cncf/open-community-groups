-- Used by attendee checkout cancellation to release an active pending purchase
create or replace function cancel_event_checkout(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
declare
    v_event_id uuid;
    v_event_discount_code_id uuid;
    v_user_id uuid;
begin
    -- Expire the attendee's active pending purchase for this event
    update event_purchase ep
    set
        hold_expires_at = current_timestamp,
        status = 'expired',
        updated_at = current_timestamp
    from event e
    join "group" g on g.group_id = e.group_id
    where ep.event_id = e.event_id
    and g.community_id = p_community_id
    and ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and ep.status = 'pending'
    and ep.hold_expires_at > current_timestamp
    returning
        ep.event_discount_code_id,
        ep.event_id,
        ep.user_id
    into
        v_event_discount_code_id,
        v_event_id,
        v_user_id;

    -- Restore any reserved discount usage released by the canceled checkout
    if v_event_discount_code_id is not null then
        perform release_event_discount_code_availability(v_event_discount_code_id);
    end if;

    -- Release the pending attendee row created for checkout answers
    if v_event_id is not null then
        perform release_event_checkout_attendee_hold(v_event_id, v_user_id);
    end if;
end;
$$ language plpgsql;
