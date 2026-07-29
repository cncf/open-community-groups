-- Releases an active admission offer and any linked checkout reservation.
create or replace function release_event_admission_offer(
    p_admission_offer_id uuid,
    p_terminal_status text,
    p_expected_group_id uuid default null,
    p_expected_user_id uuid default null,
    p_configured_provider text default null
)
returns table (
    community_id uuid,
    event_id uuid,
    event_ticket_type_id uuid,
    group_id uuid,
    organizer_user_id uuid,
    promoted_user_ids uuid[],
    source text,
    user_id uuid
) as $$
declare
    v_event_discount_code_id uuid;
    v_event_id uuid;
    v_event_ticket_type_id uuid;
    v_group_id uuid;
    v_promoted_user_ids uuid[] := array[]::uuid[];
    v_reconciled_user_ids uuid[];
    v_user_id uuid;
begin
    -- Restrict callers to the two terminal release transitions
    if p_terminal_status not in ('canceled', 'declined') then
        raise exception 'invalid admission offer release status';
    end if;

    -- Resolve immutable enrollment identifiers before taking lifecycle locks
    select
        ao.event_id,
        ao.event_ticket_type_id,
        ao.user_id
    into
        v_event_id,
        v_event_ticket_type_id,
        v_user_id
    from admission_offer ao
    where ao.admission_offer_id = p_admission_offer_id;

    if not found then
        raise exception 'admission offer is no longer available';
    end if;

    -- Lock the event before tiers, user enrollment state, offers, and purchases
    select e.group_id
    into v_group_id
    from event e
    where e.event_id = v_event_id
    and (p_expected_group_id is null or e.group_id = p_expected_group_id)
    for update of e;

    if not found then
        raise exception 'admission offer is no longer available';
    end if;

    -- Lock ticket tiers before reconciliation and offer transitions
    perform 1
    from event_ticket_type ett
    where ett.event_id = v_event_id
    order by ett.event_ticket_type_id
    for update of ett;

    -- Expire stale state before deciding whether the selected offer is active
    select reconcile_event_enrollment(
        v_event_id,
        v_event_ticket_type_id,
        p_configured_provider
    )
    into v_reconciled_user_ids;

    -- Keep non-ticketed promotions from the sweep so callers can notify them
    if v_event_ticket_type_id is null then
        v_promoted_user_ids := v_promoted_user_ids
            || coalesce(v_reconciled_user_ids, array[]::uuid[]);
    end if;

    -- Serialize the release with attendee and offer transitions
    perform pg_advisory_xact_lock(
        hashtext(v_event_id::text),
        hashtext(v_user_id::text)
    );

    -- Lock and validate the exact active offer under caller ownership constraints
    select
        g.community_id,
        ao.event_id,
        ao.event_ticket_type_id,
        e.group_id,
        ao.organizer_user_id,
        ao.source,
        ao.user_id
    into
        community_id,
        event_id,
        event_ticket_type_id,
        group_id,
        organizer_user_id,
        source,
        user_id
    from admission_offer ao
    join event e on e.event_id = ao.event_id
    join "group" g on g.group_id = e.group_id
    where ao.admission_offer_id = p_admission_offer_id
    and ao.status in ('checkout_pending', 'pending')
    and (ao.expires_at is null or ao.expires_at > current_timestamp)
    and (p_expected_group_id is null or e.group_id = p_expected_group_id)
    and (p_expected_user_id is null or ao.user_id = p_expected_user_id)
    for update of ao;

    if not found then
        raise exception 'admission offer is no longer available';
    end if;

    -- Expire a linked checkout before releasing its offer reservation
    select ep.event_discount_code_id
    into v_event_discount_code_id
    from event_purchase ep
    where ep.admission_offer_id = p_admission_offer_id
    and ep.status = 'pending'
    for update of ep;

    if found then
        update event_purchase
        set
            hold_expires_at = current_timestamp,
            status = 'expired',
            updated_at = current_timestamp
        where admission_offer_id = p_admission_offer_id
        and status = 'pending';

        if v_event_discount_code_id is not null then
            perform release_event_discount_code_availability(v_event_discount_code_id);
        end if;

        perform release_event_checkout_attendee_hold(v_event_id, v_user_id);
    end if;

    -- Persist the terminal recipient or organizer decision
    update admission_offer
    set
        status = p_terminal_status,
        updated_at = current_timestamp
    where admission_offer_id = p_admission_offer_id
    and status in ('checkout_pending', 'pending');

    if not found then
        raise exception 'admission offer is no longer available';
    end if;

    -- Fill the released reservation before returning the transition context
    select reconcile_event_enrollment(
        v_event_id,
        v_event_ticket_type_id,
        p_configured_provider
    )
    into v_reconciled_user_ids;

    if v_event_ticket_type_id is null then
        v_promoted_user_ids := v_promoted_user_ids
            || coalesce(v_reconciled_user_ids, array[]::uuid[]);
    end if;

    promoted_user_ids := v_promoted_user_ids;

    return next;
end;
$$ language plpgsql;
