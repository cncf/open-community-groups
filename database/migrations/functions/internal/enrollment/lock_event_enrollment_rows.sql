-- Takes the enrollment locks of an event in the global order used by every
-- enrollment mutation: ticket tiers, one advisory lock per affected user
-- (active offers, pending purchases, queued users of the scoped tier and the
-- optional extra user), then active offers and pending purchases. Callers lock
-- the event row first. Rejects a scoped tier that belongs to another event.
create or replace function lock_event_enrollment_rows(
    p_event_id uuid,
    p_event_ticket_type_id uuid,
    p_user_id uuid
)
returns void as $$
declare
    v_user_id uuid;
begin
    -- Lock every ticket tier in stable identifier order
    perform 1
    from event_ticket_type ett
    where ett.event_id = p_event_id
    order by ett.event_ticket_type_id
    for update of ett;

    -- Reject a scoped ticket type that does not belong to the event
    if p_event_ticket_type_id is not null
       and not exists (
            select 1
            from event_ticket_type ett
            where ett.event_id = p_event_id
            and ett.event_ticket_type_id = p_event_ticket_type_id
       ) then
        raise exception 'ticket type not found';
    end if;

    -- Acquire every affected event-user lock before enrollment row locks
    for v_user_id in
        select affected_user.user_id
        from (
            select ao.user_id
            from admission_offer ao
            where ao.event_id = p_event_id
            and admission_offer_is_active(ao.status)

            union

            select ep.user_id
            from event_purchase ep
            where ep.event_id = p_event_id
            and ep.status = 'pending'

            union

            select ew.user_id
            from event_waitlist ew
            where ew.event_id = p_event_id
            and (
                p_event_ticket_type_id is null
                or ew.event_ticket_type_id = p_event_ticket_type_id
            )

            union

            select p_user_id
            where p_user_id is not null
        ) affected_user
        order by affected_user.user_id
    loop
        perform pg_advisory_xact_lock(hashtext(p_event_id::text), hashtext(v_user_id::text));
    end loop;

    -- Lock active offers and pending purchases in stable identifier order
    perform 1
    from admission_offer ao
    where ao.event_id = p_event_id
    and admission_offer_is_active(ao.status)
    order by ao.admission_offer_id
    for update of ao;

    perform 1
    from event_purchase ep
    where ep.event_id = p_event_id
    and ep.status = 'pending'
    order by ep.event_purchase_id
    for update of ep;
end;
$$ language plpgsql;
