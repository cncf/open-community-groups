-- Validates payment readiness for paid-capable ticket configuration.
create or replace function validate_event_ticketing_payment_readiness(
    p_configured_provider text,
    p_paid_capable boolean,
    p_payment_currency_code text,
    p_payment_recipient jsonb,
    p_event_id uuid default null,
    p_event_payload jsonb default null
)
returns void as $$
declare
    v_event_kind_id text;
    v_existing_venue_country_code text;
    v_existing_venue_state_code text;
    v_existing_venue_state_name text;
    v_manual_tax_rate_ids text[];
    v_tax_behavior text;
    v_tax_calculation_mode text;
    v_venue_snapshot jsonb;
begin
    -- Skip provider requirements when every configured ticket price is zero
    if p_paid_capable is not true then
        return;
    end if;

    -- Validate the currency required by every positive ticket price
    if p_payment_currency_code is null then
        raise exception 'paid-capable events require payment_currency_code';
    end if;

    perform validate_payment_currency_code(p_payment_currency_code);

    -- Validate the server and group payment configuration
    if p_configured_provider is null then
        raise exception 'payments are not configured on this server';
    end if;

    if p_payment_recipient is null then
        raise exception 'paid-capable events require a payment recipient';
    end if;

    if coalesce(p_payment_recipient->>'provider', '') <> p_configured_provider then
        raise exception 'paid-capable events require a payment recipient for the server payments provider';
    end if;

    if nullif(btrim(p_payment_recipient->>'recipient_id'), '') is null then
        raise exception 'paid-capable events require a valid payment recipient';
    end if;

    if nullif(btrim(p_payment_recipient->>'seller_display_name'), '') is null then
        raise exception 'paid-capable events require a payment recipient seller name';
    end if;

    -- Resolve the event and venue snapshot from a mutation payload or stored row
    if p_event_payload is not null then
        -- Preserve stored codes while the deferred frontend omits the new field
        if p_event_id is not null and not (p_event_payload ? 'venue_state_code') then
            select
                e.venue_country_code,
                e.venue_state_code,
                e.venue_state_name
            into
                v_existing_venue_country_code,
                v_existing_venue_state_code,
                v_existing_venue_state_name
            from event e
            where e.event_id = p_event_id;

            -- Discard a code invalidated by a legacy country or subdivision edit
            if upper(nullif(btrim(p_event_payload->>'venue_country_code'), ''))
                    is distinct from upper(nullif(btrim(v_existing_venue_country_code), ''))
                or (
                    (
                        p_event_payload ? 'venue_state_name'
                        or p_event_payload ? 'venue_state'
                    )
                    and nullif(btrim(coalesce(
                        p_event_payload->>'venue_state_name',
                        p_event_payload->>'venue_state'
                    )), '') is distinct from nullif(btrim(v_existing_venue_state_name), '')
                ) then
                v_existing_venue_state_code := null;
            end if;
        end if;

        v_event_kind_id := p_event_payload->>'kind_id';
        v_manual_tax_rate_ids := coalesce(
            jsonb_text_array(p_event_payload->'manual_tax_rate_ids'),
            '{}'::text[]
        );
        v_tax_behavior := coalesce(nullif(p_event_payload->>'tax_behavior', ''), 'inclusive');
        v_tax_calculation_mode := coalesce(
            nullif(p_event_payload->>'tax_calculation_mode', ''),
            'automatic'
        );
        v_venue_snapshot := jsonb_build_object(
            'address', nullif(btrim(p_event_payload->>'venue_address'), ''),
            'city', nullif(btrim(p_event_payload->>'venue_city'), ''),
            'country_code', upper(nullif(btrim(p_event_payload->>'venue_country_code'), '')),
            'name', nullif(btrim(p_event_payload->>'venue_name'), ''),
            'state_code', upper(nullif(btrim(
                case
                    -- Validate an explicitly submitted subdivision code
                    when p_event_payload ? 'venue_state_code'
                        then p_event_payload->>'venue_state_code'
                    -- Reuse the persisted code while the frontend omits it
                    else v_existing_venue_state_code
                end
            ), '')),
            'state_name', nullif(
                btrim(coalesce(p_event_payload->>'venue_state_name', p_event_payload->>'venue_state')),
                ''
            ),
            'zip_code', nullif(btrim(p_event_payload->>'venue_zip_code'), '')
        );
    elsif p_event_id is not null then
        select
            e.event_kind_id,
            e.manual_tax_rate_ids,
            e.tax_behavior,
            e.tax_calculation_mode,
            jsonb_build_object(
                'address', nullif(btrim(e.venue_address), ''),
                'city', nullif(btrim(e.venue_city), ''),
                'country_code', nullif(btrim(e.venue_country_code), ''),
                'name', nullif(btrim(e.venue_name), ''),
                'state_code', nullif(btrim(e.venue_state_code), ''),
                'state_name', nullif(btrim(e.venue_state_name), ''),
                'zip_code', nullif(btrim(e.venue_zip_code), '')
            )
        into
            v_event_kind_id,
            v_manual_tax_rate_ids,
            v_tax_behavior,
            v_tax_calculation_mode,
            v_venue_snapshot
        from event e
        where e.event_id = p_event_id;

        if not found then
            raise exception 'event not found or inactive';
        end if;
    else
        raise exception 'paid-capable event readiness requires event context';
    end if;

    -- Limit paid sales to event kinds with complete physical venues
    if v_event_kind_id not in ('in-person', 'hybrid')
       or v_venue_snapshot->>'address' is null
       or v_venue_snapshot->>'city' is null
       or v_venue_snapshot->>'country_code' is null
       or v_venue_snapshot->>'name' is null
       or v_venue_snapshot->>'zip_code' is null then
        raise exception 'paid ticketing requires an in-person or hybrid event with a complete physical venue';
    end if;

    -- Require one internally consistent tax calculation path
    if v_tax_calculation_mode = 'automatic' then
        -- Reject stale manual Tax Rate selections in automatic mode
        if cardinality(v_manual_tax_rate_ids) > 0 then
            raise exception 'automatic ticket tax cannot include manual Tax Rates';
        end if;
    elsif v_tax_calculation_mode = 'manual' then
        -- Require a nonempty, unique set of usable Stripe identifiers
        if cardinality(v_manual_tax_rate_ids) = 0
           or array_position(v_manual_tax_rate_ids, null) is not null
           or exists (
                select 1
                from unnest(v_manual_tax_rate_ids) as rate_id
                where nullif(btrim(rate_id), '') is null
                or rate_id <> btrim(rate_id)
           )
           or cardinality(v_manual_tax_rate_ids) <> (
                select count(distinct rate_id)
                from unnest(v_manual_tax_rate_ids) as rate_id
           ) then
            raise exception 'manual ticket tax requires at least one unique Stripe Tax Rate';
        end if;
    elsif v_tax_calculation_mode = 'none' then
        -- Normalize no-tax events and reject stale manual Tax Rate selections
        if v_tax_behavior <> 'inclusive' or cardinality(v_manual_tax_rate_ids) > 0 then
            raise exception 'events that do not collect tax require inclusive display and no Tax Rates';
        end if;
    else
        raise exception 'unsupported ticket tax calculation mode';
    end if;
end;
$$ language plpgsql;
