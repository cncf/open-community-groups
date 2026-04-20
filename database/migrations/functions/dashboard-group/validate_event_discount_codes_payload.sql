-- validate_event_discount_codes_payload validates event discount code payloads.
create or replace function validate_event_discount_codes_payload(p_discount_codes jsonb)
returns void as $$
declare
    v_discount_code jsonb;
begin
    if p_discount_codes is null then
        return;
    end if;

    -- Reject duplicate discount codes ignoring letter case
    if exists (
        select 1
        from (
            select upper(discount_code->>'code') as code
            from jsonb_array_elements(p_discount_codes) as discount_codes(discount_code)
        ) codes
        group by code
        having count(*) > 1
    ) then
        raise exception 'discount codes must be unique per event';
    end if;

    -- Validate each supplied discount code
    for v_discount_code in select jsonb_array_elements(p_discount_codes)
    loop
        if (v_discount_code->>'event_discount_code_id') is null then
            raise exception 'discount codes require event_discount_code_id';
        end if;

        if nullif(v_discount_code->>'code', '') is null then
            raise exception 'discount codes require code';
        end if;

        if nullif(v_discount_code->>'title', '') is null then
            raise exception 'discount codes require title';
        end if;

        if (v_discount_code->>'available') is not null
           and (v_discount_code->>'available')::int < 0
        then
            raise exception 'discount code available must be greater than or equal to 0';
        end if;

        if (v_discount_code->>'total_available') is not null
           and (v_discount_code->>'total_available')::int < 0
        then
            raise exception 'discount code total_available must be greater than or equal to 0';
        end if;

        if (v_discount_code->>'available') is not null
           and (v_discount_code->>'total_available') is not null
           and (v_discount_code->>'available')::int > (v_discount_code->>'total_available')::int
        then
            raise exception 'discount code available cannot exceed total_available';
        end if;

        if (v_discount_code->>'ends_at') is not null
           and (v_discount_code->>'starts_at') is not null
           and (v_discount_code->>'ends_at')::timestamptz
               < (v_discount_code->>'starts_at')::timestamptz
        then
            raise exception 'discount code ends_at cannot be before starts_at';
        end if;

        if v_discount_code->>'kind' = 'fixed_amount' then
            if (v_discount_code->>'amount_minor') is null then
                raise exception 'fixed amount discount codes require amount_minor';
            end if;

            if (v_discount_code->>'amount_minor')::bigint <= 0 then
                raise exception 'discount code amount_minor must be greater than 0';
            end if;

            if v_discount_code->>'percentage' is not null then
                raise exception 'fixed amount discount codes cannot include percentage';
            end if;
        elsif v_discount_code->>'kind' = 'percentage' then
            if (v_discount_code->>'percentage') is null then
                raise exception 'percentage discount codes require percentage';
            end if;

            if (v_discount_code->>'percentage')::int < 1
               or (v_discount_code->>'percentage')::int > 100
            then
                raise exception 'discount percentage must be between 1 and 100';
            end if;

            if v_discount_code->>'amount_minor' is not null then
                raise exception 'percentage discount codes cannot include amount_minor';
            end if;
        else
            raise exception 'discount codes require a valid kind';
        end if;
    end loop;
end;
$$ language plpgsql;
