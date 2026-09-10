-- Enforces the settled ticketing shape of every event affected by a ticketing write.
create or replace function check_event_ticketing_consistency()
returns trigger as $$
declare
    v_event_id uuid;
    v_event_ids uuid[];
    v_has_discount_codes boolean;
    v_has_positive_pricing boolean;
    v_payment_currency_code text;
begin
    -- Resolve affected events from tables that carry the event identifier
    if tg_table_name in ('event', 'event_discount_code', 'event_ticket_type') then
        -- Use the inserted row's event
        if tg_op = 'INSERT' then
            v_event_ids := array[new.event_id];

        -- Use the deleted row's event
        elsif tg_op = 'DELETE' then
            v_event_ids := array[old.event_id];

        -- Use both sides of a row move
        else
            v_event_ids := array[old.event_id, new.event_id];
        end if;

    -- Resolve affected events through the price window's ticket type
    elsif tg_table_name = 'event_ticket_price_window' then
        -- Use the inserted window's ticket type
        if tg_op = 'INSERT' then
            select array_agg(distinct ett.event_id) into v_event_ids
            from event_ticket_type ett
            where ett.event_ticket_type_id = new.event_ticket_type_id;

        -- Use the deleted window's ticket type
        elsif tg_op = 'DELETE' then
            select array_agg(distinct ett.event_id) into v_event_ids
            from event_ticket_type ett
            where ett.event_ticket_type_id = old.event_ticket_type_id;

        -- Use both sides of a window move
        else
            select array_agg(distinct ett.event_id) into v_event_ids
            from event_ticket_type ett
            where ett.event_ticket_type_id = any(array[
                old.event_ticket_type_id,
                new.event_ticket_type_id
            ]);
        end if;

    -- Reject wiring on any other table
    else
        raise exception 'unsupported event ticketing consistency trigger table: %', tg_table_name;
    end if;

    -- Enforce the settled ticketing shape for each affected event
    foreach v_event_id in array coalesce(v_event_ids, array[]::uuid[])
    loop
        -- Skip missing identifiers from orphaned windows
        if v_event_id is null then
            continue;
        end if;

        -- Load the event's discount, pricing, and currency state
        select
            exists(
                select 1
                from event_discount_code edc
                where edc.event_id = e.event_id
            ),
            exists(
                select 1
                from event_ticket_type ett
                join event_ticket_price_window etpw using (event_ticket_type_id)
                where ett.event_id = e.event_id
                and etpw.amount_minor > 0
            ),
            e.payment_currency_code
        into
            v_has_discount_codes,
            v_has_positive_pricing,
            v_payment_currency_code
        from event e
        where e.event_id = v_event_id;

        -- Skip events deleted within the same statement
        if not found then
            continue;
        end if;

        -- Reject paid pricing without a currency
        if v_has_positive_pricing and v_payment_currency_code is null then
            raise exception 'positive ticket pricing requires payment_currency_code' using errcode = 'OCG01';
        end if;

        -- Reject discount codes on free events
        if not v_has_positive_pricing and v_has_discount_codes then
            raise exception 'discount_codes require positive ticket pricing' using errcode = 'OCG01';
        end if;

        -- Reject a currency on free events
        if not v_has_positive_pricing and v_payment_currency_code is not null then
            raise exception 'payment_currency_code requires positive ticket pricing' using errcode = 'OCG01';
        end if;
    end loop;

    -- Constraint triggers ignore the returned row
    return null;
end;
$$ language plpgsql;
