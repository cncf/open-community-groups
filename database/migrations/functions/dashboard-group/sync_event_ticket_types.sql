-- sync_event_ticket_types upserts and prunes event ticket types.
create or replace function sync_event_ticket_types(
    p_event_id uuid,
    p_ticket_types jsonb
)
returns void as $$
declare
    v_active_purchase_count int;
    v_price_window jsonb;
    v_price_window_ids uuid[];
    v_ticket_type jsonb;
    v_ticket_type_id uuid;
    v_ticket_type_ids uuid[] := coalesce(
        array(
            select (ticket_type->>'event_ticket_type_id')::uuid
            from jsonb_array_elements(coalesce(p_ticket_types, '[]'::jsonb))
                as ticket_types(ticket_type)
        ),
        '{}'::uuid[]
    );
begin
    -- Reject ticket type identifiers that belong to a different event
    if exists (
        select 1
        from event_ticket_type ett
        where ett.event_ticket_type_id = any(v_ticket_type_ids)
        and ett.event_id <> p_event_id
    ) then
        raise exception 'ticket type does not belong to event';
    end if;

    -- Reject price window identifiers that belong to a different event
    if exists (
        select 1
        from jsonb_array_elements(coalesce(p_ticket_types, '[]'::jsonb)) as ticket_types(ticket_type)
        cross join lateral jsonb_array_elements(
            coalesce(ticket_type->'price_windows', '[]'::jsonb)
        ) as price_windows(price_window)
        join event_ticket_price_window etpw
            on etpw.event_ticket_price_window_id
                = (price_window->>'event_ticket_price_window_id')::uuid
        join event_ticket_type ett on ett.event_ticket_type_id = etpw.event_ticket_type_id
        where ett.event_id <> p_event_id
    ) then
        raise exception 'ticket price window does not belong to event';
    end if;

    -- Prevent removing ticket types that are already linked to purchases
    if exists (
        select 1
        from event_ticket_type ett
        join event_purchase ep on ep.event_ticket_type_id = ett.event_ticket_type_id
        where ett.event_id = p_event_id
        and not (ett.event_ticket_type_id = any(v_ticket_type_ids))
    ) then
        raise exception 'ticket types with purchases cannot be removed; deactivate them instead';
    end if;

    -- Prune omitted ticket types after integrity checks
    delete from event_ticket_type
    where event_id = p_event_id
    and not (event_ticket_type_id = any(v_ticket_type_ids));

    -- Upsert provided ticket types and their price windows
    for v_ticket_type in
        select jsonb_array_elements(coalesce(p_ticket_types, '[]'::jsonb))
    loop
        v_ticket_type_id := (v_ticket_type->>'event_ticket_type_id')::uuid;

        -- Reject seat totals that would undershoot purchased inventory
        select count(*)::int
        into v_active_purchase_count
        from event_purchase ep
        where ep.event_id = p_event_id
        and ep.event_ticket_type_id = v_ticket_type_id
        and ep.status in ('completed', 'pending', 'refund-requested')
        and (
            ep.status <> 'pending'
            or ep.hold_expires_at > current_timestamp
        );

        if coalesce((v_ticket_type->>'seats_total')::int, 0) < v_active_purchase_count then
            raise exception
                'ticket type seats_total (%) cannot be less than current number of purchased seats (%)',
                coalesce((v_ticket_type->>'seats_total')::int, 0),
                v_active_purchase_count;
        end if;

        -- Upsert the ticket type row with normalized defaults
        insert into event_ticket_type (
            event_ticket_type_id,
            active,
            description,
            event_id,
            "order",
            seats_total,
            title
        ) values (
            v_ticket_type_id,
            coalesce((v_ticket_type->>'active')::boolean, true),
            nullif(v_ticket_type->>'description', ''),
            p_event_id,
            coalesce((v_ticket_type->>'order')::int, 0),
            coalesce((v_ticket_type->>'seats_total')::int, 0),
            v_ticket_type->>'title'
        )
        on conflict (event_ticket_type_id) do update
        set
            active = excluded.active,
            description = excluded.description,
            "order" = excluded."order",
            seats_total = excluded.seats_total,
            title = excluded.title,
            updated_at = current_timestamp;

        -- Collect the price window identifiers supplied for this ticket type
        v_price_window_ids := coalesce(
            array(
                select (price_window->>'event_ticket_price_window_id')::uuid
                from jsonb_array_elements(coalesce(v_ticket_type->'price_windows', '[]'::jsonb))
                    as price_windows(price_window)
            ),
            '{}'::uuid[]
        );

        -- Reject price window identifiers that already belong to another ticket type
        if exists (
            select 1
            from event_ticket_price_window etpw
            where etpw.event_ticket_price_window_id = any(v_price_window_ids)
            and etpw.event_ticket_type_id <> v_ticket_type_id
        ) then
            raise exception 'ticket price window does not belong to ticket type';
        end if;

        -- Prune omitted price windows before upserting the payload
        delete from event_ticket_price_window
        where event_ticket_type_id = v_ticket_type_id
        and not (event_ticket_price_window_id = any(v_price_window_ids));

        -- Upsert the remaining price windows for this ticket type
        for v_price_window in
            select jsonb_array_elements(coalesce(v_ticket_type->'price_windows', '[]'::jsonb))
        loop
            insert into event_ticket_price_window (
                event_ticket_price_window_id,
                amount_minor,
                ends_at,
                event_ticket_type_id,
                starts_at
            ) values (
                (v_price_window->>'event_ticket_price_window_id')::uuid,
                (v_price_window->>'amount_minor')::bigint,
                (v_price_window->>'ends_at')::timestamptz,
                v_ticket_type_id,
                (v_price_window->>'starts_at')::timestamptz
            )
            on conflict (event_ticket_price_window_id) do update
            set
                amount_minor = excluded.amount_minor,
                ends_at = excluded.ends_at,
                starts_at = excluded.starts_at,
                updated_at = current_timestamp;
        end loop;
    end loop;
end;
$$ language plpgsql;
