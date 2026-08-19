-- Reports whether an event mutation changes fields that govern paid ticket readiness.
create or replace function event_ticketing_configuration_changed(
    p_event_before jsonb,
    p_event jsonb
)
returns boolean as $$
declare
    v_discount_codes jsonb;
    v_ends_at timestamptz;
    v_payment_became_active boolean;
    v_payment_currency_code text;
    v_performance_context_changed boolean;
    v_pricing_configuration_changed boolean;
    v_starts_at timestamptz;
    v_tax_configuration_changed boolean;
    v_ticket_types jsonb;
    v_ticket_types_before_configuration jsonb;
    v_ticket_types_configuration jsonb;
    v_timezone text;
    v_was_payment_active boolean;
    v_will_payment_active boolean;
begin
    -- Resolve effective ticketing and schedule inputs from the partial payload
    v_discount_codes := case
        when p_event ? 'discount_codes'
        then nullif(p_event->'discount_codes', 'null'::jsonb)
        else p_event_before->'discount_codes'
    end;
    v_ticket_types := case
        when p_event ? 'ticket_types'
        then nullif(p_event->'ticket_types', 'null'::jsonb)
        else p_event_before->'ticket_types'
    end;
    v_payment_currency_code := case
        when p_event ? 'payment_currency_code'
        then nullif(p_event->>'payment_currency_code', '')
        else nullif(p_event_before->>'payment_currency_code', '')
    end;
    v_timezone := coalesce(
        nullif(p_event->>'timezone', ''),
        nullif(p_event_before->>'timezone', ''),
        'UTC'
    );
    v_starts_at := case
        when p_event ? 'starts_at'
        then nullif(p_event->>'starts_at', '')::timestamp at time zone v_timezone
        else to_timestamp((p_event_before->>'starts_at')::double precision)
    end;
    v_ends_at := case
        when p_event ? 'ends_at'
        then nullif(p_event->>'ends_at', '')::timestamp at time zone v_timezone
        else to_timestamp((p_event_before->>'ends_at')::double precision)
    end;

    -- Resolve the prior and proposed paid-ticketing activity states
    v_was_payment_active := coalesce((p_event_before->>'published')::boolean, false)
        and (
            coalesce(
                to_timestamp((p_event_before->>'ends_at')::double precision),
                to_timestamp((p_event_before->>'starts_at')::double precision)
            ) is null
            or coalesce(
                to_timestamp((p_event_before->>'ends_at')::double precision),
                to_timestamp((p_event_before->>'starts_at')::double precision)
            ) > current_timestamp
        );
    v_will_payment_active := coalesce((p_event_before->>'published')::boolean, false)
        and (
            coalesce(v_ends_at, v_starts_at) is null
            or coalesce(v_ends_at, v_starts_at) > current_timestamp
        );
    v_payment_became_active := not v_was_payment_active and v_will_payment_active;

    -- Ignore read-model-only ticket fields when comparing stored configuration
    select coalesce(
        jsonb_agg(
            ticket_type - 'current_price' - 'remaining_seats' - 'sold_out'
            order by ordinality
        ),
        '[]'::jsonb
    )
    into v_ticket_types_before_configuration
    from jsonb_array_elements(coalesce(p_event_before->'ticket_types', '[]'::jsonb))
        with ordinality as ticket_types(ticket_type, ordinality);

    -- Ignore read-model-only ticket fields in the proposed configuration
    select coalesce(
        jsonb_agg(
            ticket_type - 'current_price' - 'remaining_seats' - 'sold_out'
            order by ordinality
        ),
        '[]'::jsonb
    )
    into v_ticket_types_configuration
    from jsonb_array_elements(coalesce(v_ticket_types, '[]'::jsonb))
        with ordinality as ticket_types(ticket_type, ordinality);

    -- Compare the taxable performance context
    v_performance_context_changed :=
        p_event->>'kind_id' is distinct from p_event_before->>'kind'
        or nullif(btrim(p_event->>'venue_address'), '')
            is distinct from nullif(btrim(p_event_before->>'venue_address'), '')
        or nullif(btrim(p_event->>'venue_city'), '')
            is distinct from nullif(btrim(p_event_before->>'venue_city'), '')
        or nullif(btrim(p_event->>'venue_country_code'), '')
            is distinct from nullif(btrim(p_event_before->>'venue_country_code'), '')
        or nullif(btrim(p_event->>'venue_name'), '')
            is distinct from nullif(btrim(p_event_before->>'venue_name'), '')
        or upper(nullif(btrim(
            case
                when p_event ? 'venue_state_code' then p_event->>'venue_state_code'
                else p_event_before->>'venue_state_code'
            end
        ), ''))
            is distinct from upper(nullif(btrim(p_event_before->>'venue_state_code'), ''))
        or nullif(btrim(coalesce(p_event->>'venue_state_name', p_event->>'venue_state')), '')
            is distinct from nullif(btrim(p_event_before->>'venue_state_name'), '')
        or nullif(btrim(p_event->>'venue_zip_code'), '')
            is distinct from nullif(btrim(p_event_before->>'venue_zip_code'), '');

    -- Compare ticket inventory and pricing inputs
    v_pricing_configuration_changed :=
        v_discount_codes is distinct from p_event_before->'discount_codes'
        or v_payment_currency_code is distinct from nullif(
            p_event_before->>'payment_currency_code',
            ''
        )
        or v_ticket_types_configuration
            is distinct from v_ticket_types_before_configuration;

    -- Compare tax policy inputs
    v_tax_configuration_changed :=
        case
            when p_event ? 'manual_tax_rate_ids'
            then coalesce(p_event->'manual_tax_rate_ids', '[]'::jsonb)
            else coalesce(p_event_before->'manual_tax_rate_ids', '[]'::jsonb)
        end
            is distinct from coalesce(p_event_before->'manual_tax_rate_ids', '[]'::jsonb)
        or case
            when p_event ? 'tax_behavior'
            then coalesce(nullif(p_event->>'tax_behavior', ''), 'inclusive')
            else coalesce(nullif(p_event_before->>'tax_behavior', ''), 'inclusive')
        end
            is distinct from coalesce(p_event_before->>'tax_behavior', 'inclusive')
        or case
            when p_event ? 'tax_calculation_mode'
            then coalesce(nullif(p_event->>'tax_calculation_mode', ''), 'automatic')
            else coalesce(nullif(p_event_before->>'tax_calculation_mode', ''), 'automatic')
        end
            is distinct from coalesce(
                p_event_before->>'tax_calculation_mode',
                'automatic'
            );

    -- Report changes that can govern a paid purchase
    return is_event_ticketing_payload_paid_capable(v_ticket_types) and (
        v_payment_became_active
        or v_performance_context_changed
        or v_pricing_configuration_changed
        or v_tax_configuration_changed
    );
end;
$$ language plpgsql stable;
