-- Completes a pending free-ticket purchase and returns its notification data.
create or replace function complete_free_event_purchase(
    p_event_purchase_id uuid
)
returns jsonb as $$
declare
    v_admission_offer_id uuid;
    v_amount_minor bigint;
    v_community_id uuid;
    v_event_canceled boolean;
    v_event_deleted boolean;
    v_event_ends_at timestamptz;
    v_event_id uuid;
    v_event_published boolean;
    v_event_starts_at timestamptz;
    v_event_ticket_type_id uuid;
    v_group_id uuid;
    v_group_active boolean;
    v_hold_expires_at timestamptz;
    v_manually_invited boolean;
    v_purchase_hold_expired boolean;
    v_recovery_pending boolean;
    v_status text;
    v_user_id uuid;
begin
    -- Resolve immutable parent identifiers before taking locks
    select
        ep.event_id,
        e.group_id,
        ep.event_ticket_type_id,
        ep.status in ('expired', 'pending')
            and ep.hold_expires_at is not null
            and ep.hold_expires_at <= current_timestamp
    into
        v_event_id,
        v_group_id,
        v_event_ticket_type_id,
        v_purchase_hold_expired
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    where ep.event_purchase_id = p_event_purchase_id;

    if not found then
        raise exception 'purchase not found';
    end if;

    if v_purchase_hold_expired then
        raise exception 'purchase hold has expired';
    end if;

    -- Lock the group before the event to match dashboard event mutations
    select g.active, g.community_id
    into v_group_active, v_community_id
    from "group" g
    where g.group_id = v_group_id
    for update of g;

    if not found then
        raise exception 'purchase not found';
    end if;

    -- Lock the event before the purchase to match checkout and attendance flows
    select
        e.canceled,
        e.deleted,
        e.ends_at,
        e.published,
        e.starts_at
    into
        v_event_canceled,
        v_event_deleted,
        v_event_ends_at,
        v_event_published,
        v_event_starts_at
    from event e
    where e.event_id = v_event_id
    and e.group_id = v_group_id
    for update of e;

    if not found then
        raise exception 'purchase not found';
    end if;

    -- Reconcile under the global event, tier, user, and purchase lock order
    perform reconcile_event_enrollment(v_event_id, v_event_ticket_type_id);

    -- Lock the purchase before validating and completing it
    select
        ep.admission_offer_id,
        ep.amount_minor,
        ep.hold_expires_at,
        coalesce(ao.source = 'organizer_invitation', false),
        exists (
            select 1
            from event_purchase recovery_ep
            where recovery_ep.event_id = ep.event_id
            and recovery_ep.event_purchase_id <> ep.event_purchase_id
            and recovery_ep.status = 'refund-recovery-pending'
            and recovery_ep.user_id = ep.user_id
        ),
        ep.status,
        ep.user_id
    into
        v_admission_offer_id,
        v_amount_minor,
        v_hold_expires_at,
        v_manually_invited,
        v_recovery_pending,
        v_status,
        v_user_id
    from event_purchase ep
    left join admission_offer ao
        on ao.admission_offer_id = ep.admission_offer_id
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

    if v_recovery_pending then
        raise exception 'checkout is unavailable while refund recovery is in progress';
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

    -- Complete the linked reservation before creating active attendance
    if v_admission_offer_id is not null then
        update admission_offer
        set
            status = 'completed',
            updated_at = current_timestamp
        where admission_offer_id = v_admission_offer_id
        and status = 'checkout_pending';

        if not found then
            raise exception 'admission offer is no longer available';
        end if;
    end if;

    -- Add the attendee and persist the completed free purchase
    insert into event_attendee (event_id, user_id, manually_invited)
    values (v_event_id, v_user_id, v_manually_invited)
    on conflict (event_id, user_id) do update
    set
        attendance_canceled_at = null,
        attendance_canceled_by_user_id = null,
        manually_invited = excluded.manually_invited,
        status = 'confirmed'
    where event_attendee.status in (
        'attendance-canceled',
        'confirmed',
        'invitation-canceled',
        'registration-questions-pending'
    );

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
