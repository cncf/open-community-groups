-- get_event_ticket_capacity sums all non-negative ticket seats in a payload.
create or replace function get_event_ticket_capacity(p_ticket_types jsonb)
returns int as $$
begin
    if p_ticket_types is null then
        return null;
    end if;

    return (
        select coalesce(sum(greatest((ticket_type->>'seats_total')::int, 0)), 0)::int
        from jsonb_array_elements(p_ticket_types) as ticket_types(ticket_type)
    );
end;
$$ language plpgsql;
