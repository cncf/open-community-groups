-- Used by start_checkout for zero-amount tickets: validates that the pending
-- purchase is still a live free hold, adds the attendee, marks it completed,
-- and returns identifiers for the welcome notification flow
create or replace function complete_free_event_purchase(
    p_event_purchase_id uuid
)
returns jsonb as $$
declare
    v_amount_minor bigint;
    v_community_id uuid;
    v_event_id uuid;
    v_hold_expires_at timestamptz;
    v_status text;
    v_user_id uuid;
begin
    -- Lock the purchase before validating and completing it
    select
        ep.amount_minor,
        g.community_id,
        ep.event_id,
        ep.hold_expires_at,
        ep.status,
        ep.user_id
    into
        v_amount_minor,
        v_community_id,
        v_event_id,
        v_hold_expires_at,
        v_status,
        v_user_id
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    where ep.event_purchase_id = p_event_purchase_id
    for update of ep;

    if not found then
        raise exception 'purchase not found';
    end if;

    -- Validate that the locked purchase is still eligible for local completion
    if v_status <> 'pending' then
        raise exception 'purchase is no longer pending';
    end if;

    if v_amount_minor <> 0 then
        raise exception 'only free purchases can be completed locally';
    end if;

    if v_hold_expires_at is not null and v_hold_expires_at <= current_timestamp then
        raise exception 'purchase hold has expired';
    end if;

    -- Add the attendee and persist the completed free purchase
    insert into event_attendee (event_id, user_id)
    values (v_event_id, v_user_id)
    on conflict (event_id, user_id) do nothing;

    update event_purchase
    set
        completed_at = current_timestamp,
        hold_expires_at = null,
        status = 'completed',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id;

    -- Return the identifiers needed by the caller after completion
    return jsonb_build_object(
        'community_id', v_community_id,
        'event_id', v_event_id,
        'user_id', v_user_id
    );
end;
$$ language plpgsql;
