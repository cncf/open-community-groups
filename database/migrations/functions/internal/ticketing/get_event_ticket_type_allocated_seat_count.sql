-- Returns the number of seats allocated for an event ticket type.
-- Uses PL/pgSQL with `force_generic_plan` so each connection caches its plan:
-- list_event_ticket_types runs once per event in event lists, and a
-- SQL-language body is planned again each time that list runs (PostgreSQL 17
-- and earlier). The setting also keeps a caller's `force_custom_plan` from
-- planning it on every call.
create or replace function get_event_ticket_type_allocated_seat_count(
    p_event_id uuid,
    p_event_ticket_type_id uuid
)
returns int as $$
begin
    -- Count the seats allocated to the ticket type
    return (
        select (
            (
                -- Count live offers reserving the tier
                select count(*)
                from admission_offer ao
                where ao.event_id = p_event_id
                and ao.event_ticket_type_id = p_event_ticket_type_id
                and admission_offer_reserves_seat(ao.status, ao.expires_at)
            )
            +
            (
                -- Purchases without an offer are distinct by primary key and count
                -- individually; purchases sharing an offer count once
                select
                    count(*) filter (where ep.admission_offer_id is null)
                    + count(distinct ep.admission_offer_id)
                from event_purchase ep
                where ep.event_id = p_event_id
                and ep.event_ticket_type_id = p_event_ticket_type_id
                and event_purchase_reserves_seat(ep.status, ep.hold_expires_at)
                -- Skip purchases whose offer is already counted
                and not exists (
                    select 1
                    from admission_offer ao
                    where ao.admission_offer_id = ep.admission_offer_id
                    and admission_offer_reserves_seat(ao.status, ao.expires_at)
                )
            )
        )::int
    );
end;
$$ language plpgsql stable set plan_cache_mode = force_generic_plan;
