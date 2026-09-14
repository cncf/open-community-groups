-- sync_event_discount_codes upserts and prunes event discount codes.
-- Callers hold the owning group and event row locks because deferred ticketing
-- consistency triggers rely on that serialization.
create or replace function sync_event_discount_codes(
    p_event_id uuid,
    p_discount_codes jsonb
)
returns void as $$
declare
    v_available_override_active boolean;
    v_discount_code jsonb;
    v_discount_code_ids uuid[] := coalesce(
        array(
            select (discount_code->>'event_discount_code_id')::uuid
            from jsonb_array_elements(coalesce(p_discount_codes, '[]'::jsonb))
                as discount_codes(discount_code)
        ),
        '{}'::uuid[]
    );
begin
    -- Reject payload identifiers that belong to a different event
    if exists (
        select 1
        from event_discount_code edc
        where edc.event_discount_code_id = any(v_discount_code_ids)
        and edc.event_id <> p_event_id
    ) then
        raise exception 'discount code does not belong to event' using errcode = 'OCG01';
    end if;

    -- Prevent lowering total_available below existing redemptions
    if exists (
        select 1
        from jsonb_array_elements(coalesce(p_discount_codes, '[]'::jsonb))
            as discount_codes(discount_code)
        join event_discount_code edc
            on edc.event_discount_code_id =
                (discount_code->>'event_discount_code_id')::uuid
        where edc.event_id = p_event_id
        and (discount_code->>'total_available') is not null
        and (
            select count(*)::int
            from event_purchase ep
            where ep.event_id = p_event_id
            and ep.event_discount_code_id = edc.event_discount_code_id
            and (
                ep.status in ('completed', 'refund-requested')
                or (
                    ep.status = 'pending'
                    and ep.hold_expires_at > current_timestamp
                )
            )
        ) > (discount_code->>'total_available')::int
    ) then
        raise exception 'discount code total_available cannot be less than existing redemptions' using errcode = 'OCG01';
    end if;

    -- Prevent removing discount codes that are already linked to purchases
    if exists (
        select 1
        from event_discount_code edc
        join event_purchase ep on ep.event_discount_code_id = edc.event_discount_code_id
        where edc.event_id = p_event_id
        and not (edc.event_discount_code_id = any(v_discount_code_ids))
    ) then
        raise exception 'discount codes with redemptions cannot be removed; deactivate them instead' using errcode = 'OCG01';
    end if;

    -- Prune omitted discount codes after integrity checks
    delete from event_discount_code
    where event_id = p_event_id
    and not (event_discount_code_id = any(v_discount_code_ids));

    -- Upsert provided discount codes
    for v_discount_code in
        select jsonb_array_elements(coalesce(p_discount_codes, '[]'::jsonb))
    loop
        -- Resolve whether Uses remaining should stay in manual override mode
        v_available_override_active := resolve_event_discount_code_available_override(v_discount_code);

        -- Upsert the code, keeping the stored count when the override stays on
        insert into event_discount_code (
            event_discount_code_id,
            active,
            available,
            available_override_active,
            amount_minor,
            code,
            ends_at,
            event_id,
            kind,
            percentage,
            starts_at,
            title,
            total_available
        ) values (
            (v_discount_code->>'event_discount_code_id')::uuid,
            coalesce((v_discount_code->>'active')::boolean, true),
            (v_discount_code->>'available')::int,
            v_available_override_active,
            (v_discount_code->>'amount_minor')::bigint,
            v_discount_code->>'code',
            (v_discount_code->>'ends_at')::timestamptz,
            p_event_id,
            v_discount_code->>'kind',
            (v_discount_code->>'percentage')::int,
            (v_discount_code->>'starts_at')::timestamptz,
            v_discount_code->>'title',
            (v_discount_code->>'total_available')::int
        )
        on conflict (event_discount_code_id) do update
        set
            active = excluded.active,
            available = case
                -- Keep or replace the manual count while the override stays on
                when resolve_event_discount_code_available_override(
                    v_discount_code,
                    event_discount_code.available_override_active
                ) then coalesce(excluded.available, event_discount_code.available)
                -- Drop the manual count once the override is off
                else null
            end,
            available_override_active = resolve_event_discount_code_available_override(
                v_discount_code,
                event_discount_code.available_override_active
            ),
            amount_minor = excluded.amount_minor,
            code = excluded.code,
            ends_at = excluded.ends_at,
            kind = excluded.kind,
            percentage = excluded.percentage,
            starts_at = excluded.starts_at,
            title = excluded.title,
            total_available = excluded.total_available,
            updated_at = current_timestamp;
    end loop;
end;
$$ language plpgsql;
