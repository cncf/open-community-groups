-- Reports the conflict an organizer-issued admission offer would cause on a
-- full ticket tier: queue-has-priority when the reconciliation that preceded
-- the offer promoted waitlist users into the remaining seats, ticket-type-sold-out
-- otherwise. Returns null while the tier has capacity.
create or replace function admission_offer_capacity_conflict(
    p_ticket_type event_ticket_type,
    p_promoted_user_ids uuid[]
)
returns text as $$
    select case
        -- Keep issuing offers while seats remain
        when p_ticket_type.seats_total is null
            or get_event_ticket_type_allocated_seat_count(p_ticket_type.event_id, p_ticket_type.event_ticket_type_id)
                < p_ticket_type.seats_total
            then null
        -- Keep queue heads ahead of organizer offers
        when cardinality(p_promoted_user_ids) > 0 then 'queue-has-priority'
        -- Report a full tier when no queued user was promoted
        else 'ticket-type-sold-out'
    end;
$$ language sql;
