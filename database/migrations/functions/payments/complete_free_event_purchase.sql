-- Used by start_checkout for zero-amount tickets: validates that the pending
-- purchase is still a live free hold, adds the attendee, marks it completed,
-- and returns identifiers for the welcome notification flow
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
    -- Lock the purchase before validating and completing it
    select
        ep.amount_minor,
        e.canceled,
        e.deleted,
        e.ends_at,
        g.community_id,
        ep.event_id,
        ep.hold_expires_at,
        e.published,
        ep.status,
        e.starts_at,
        g.active,
        ep.user_id
    into
        v_amount_minor,
        v_event_canceled,
        v_event_deleted,
        v_event_ends_at,
        v_community_id,
        v_event_id,
        v_hold_expires_at,
        v_event_published,
        v_status,
        v_event_starts_at,
        v_group_active,
        v_user_id
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    where ep.event_purchase_id = p_event_purchase_id
    for update of ep, e, g;

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
