-- Completes a pending free-ticket purchase and returns its notification data.
create or replace function complete_free_event_purchase(
    p_event_purchase_id uuid
)
returns jsonb as $$
declare
    v_amount_minor bigint;
    v_event_canceled boolean;
    v_event_deleted boolean;
    v_event_ends_at timestamptz;
    v_community_id uuid;
    v_event_id uuid;
    v_hold_expires_at timestamptz;
    v_event_published boolean;
    v_event_starts_at timestamptz;
    v_group_active boolean;
    v_status text;
    v_user_id uuid;
begin
    -- Resolve the purchase event without locking so the event row can be
    -- locked before the purchase row (event_id is immutable on purchases)
    select ep.event_id into v_event_id
    from event_purchase ep
    where ep.event_purchase_id = p_event_purchase_id;

    if not found then
        raise exception 'purchase not found';
    end if;

    -- Lock the event and group first to keep a consistent event -> purchase
    -- lock order with prepare_event_checkout_purchase
    select
        e.canceled,
        e.deleted,
        e.ends_at,
        g.community_id,
        e.published,
        e.starts_at,
        g.active
    into
        v_event_canceled,
        v_event_deleted,
        v_event_ends_at,
        v_community_id,
        v_event_published,
        v_event_starts_at,
        v_group_active
    from event e
    join "group" g on g.group_id = e.group_id
    where e.event_id = v_event_id
    for update of e, g;

    if not found then
        raise exception 'purchase not found';
    end if;

    -- Lock the purchase before validating and completing it
    select
        ep.amount_minor,
        ep.hold_expires_at,
        ep.status,
        ep.user_id
    into
        v_amount_minor,
        v_hold_expires_at,
        v_status,
        v_user_id
    from event_purchase ep
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

    -- Ensure the event is still active before completing the free purchase
    if not v_group_active
       or v_event_deleted
       or not v_event_published
       or v_event_canceled
       or (
           coalesce(v_event_ends_at, v_event_starts_at) is not null
           and coalesce(v_event_ends_at, v_event_starts_at) <= current_timestamp
       ) then
        raise exception 'event not found or inactive';
    end if;

    -- Add the attendee and persist the completed free purchase
    insert into event_attendee (event_id, user_id)
    values (v_event_id, v_user_id)
    on conflict (event_id, user_id) do update
    set status = 'confirmed'
    where event_attendee.status in ('confirmed', 'invitation-canceled', 'registration-questions-pending');

    -- Never complete the purchase without a confirmed attendee row
    if not found then
        raise exception 'attendee cannot be confirmed for this event';
    end if;

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
