-- validate_event_ticket_types_payload validates event ticket type payloads.
create or replace function validate_event_ticket_types_payload(p_ticket_types jsonb)
returns void as $$
declare
    v_ticket_type jsonb;
begin
    if p_ticket_types is null then
        return;
    end if;

    -- Validate each supplied ticket type and its price windows
    for v_ticket_type in select jsonb_array_elements(p_ticket_types)
    loop
        if (v_ticket_type->>'event_ticket_type_id') is null then
            raise exception 'ticket types require event_ticket_type_id';
        end if;

        if nullif(v_ticket_type->>'title', '') is null then
            raise exception 'ticket types require title';
        end if;

        if (v_ticket_type->>'seats_total') is null then
            raise exception 'ticket types require seats_total';
        end if;

        if (v_ticket_type->>'seats_total')::int < 0 then
            raise exception 'ticket type seats_total must be greater than or equal to 0';
        end if;

        if coalesce(jsonb_typeof(v_ticket_type->'price_windows'), '') <> 'array' then
            raise exception 'ticket types require at least one price window';
        end if;

        if jsonb_array_length(v_ticket_type->'price_windows') = 0 then
            raise exception 'ticket types require at least one price window';
        end if;

        if exists (
            select 1
            from jsonb_array_elements(v_ticket_type->'price_windows') as price_windows(price_window)
            where (price_window->>'event_ticket_price_window_id') is null
        ) then
            raise exception 'ticket price windows require event_ticket_price_window_id';
        end if;

        if exists (
            select 1
            from jsonb_array_elements(v_ticket_type->'price_windows') as price_windows(price_window)
            where (price_window->>'amount_minor') is null
               or (price_window->>'amount_minor')::bigint < 0
               or (
                   (price_window->>'ends_at') is not null
                   and (price_window->>'starts_at') is not null
                   and (price_window->>'ends_at')::timestamptz
                       < (price_window->>'starts_at')::timestamptz
               )
        ) then
            raise exception 'ticket price windows must have non-negative amounts and valid date ranges';
        end if;

        if exists (
            with price_windows as (
                select
                    tstzrange(
                        coalesce((price_window->>'starts_at')::timestamptz, '-infinity'::timestamptz),
                        coalesce((price_window->>'ends_at')::timestamptz, 'infinity'::timestamptz),
                        '[]'
                    ) as active_window,
                    ordinality
                from jsonb_array_elements(v_ticket_type->'price_windows')
                    with ordinality as price_windows(price_window, ordinality)
            )
            select 1
            from price_windows pw1
            join price_windows pw2 on pw1.ordinality < pw2.ordinality
            where pw1.active_window && pw2.active_window
        ) then
            raise exception 'ticket price windows cannot overlap';
        end if;
    end loop;
end;
$$ language plpgsql;
