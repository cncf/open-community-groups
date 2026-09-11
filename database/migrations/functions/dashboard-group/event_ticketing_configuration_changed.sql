-- Reports whether an event update payload changes fields that govern paid
-- ticket readiness (pricing, tax policy, external payment settings, taxable
-- performance context or the event becoming purchasable). The prior state is
-- read from the event row and its stored ticket types and discount codes;
-- payload keys the dashboard may omit fall back to the stored values. Ticket
-- types and discount codes are compared on their configuration projections
-- (event_ticket_types_configuration, event_discount_codes_configuration) so
-- read-model fields, live inventory, ordering and timestamp spellings never
-- register as changes.
create or replace function event_ticketing_configuration_changed(
    p_community_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_event jsonb
)
returns boolean as $$
declare
    v_before event;
    v_discount_codes jsonb;
    v_discount_codes_before jsonb;
    v_ends_at timestamptz;
    v_external_configuration_changed boolean;
    v_payment_became_active boolean;
    v_payment_currency_code text;
    v_performance_context_changed boolean;
    v_pricing_configuration_changed boolean;
    v_starts_at timestamptz;
    v_tax_configuration_changed boolean;
    v_ticket_types jsonb;
    v_ticket_types_before jsonb;
    v_timezone text;
    v_was_payment_active boolean;
    v_will_payment_active boolean;
begin
    -- Load the event scoped to its group and community
    select e.*
    into v_before
    from event e
    join "group" g on g.group_id = e.group_id
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and g.community_id = p_community_id;

    -- Reject events outside the scope
    if not found then
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;

    -- Load the stored ticket configuration
    v_discount_codes_before := list_event_discount_codes(p_event_id);
    v_ticket_types_before := list_event_ticket_types(p_event_id);

    -- Resolve effective ticketing and schedule inputs from the partial payload
    v_discount_codes := case
        -- Use the submitted discount codes
        when p_event ? 'discount_codes' then nullif(p_event->'discount_codes', 'null'::jsonb)
        -- Preserve the stored discount codes
        else v_discount_codes_before
    end;
    v_ticket_types := case
        -- Use the submitted ticket types
        when p_event ? 'ticket_types' then nullif(p_event->'ticket_types', 'null'::jsonb)
        -- Preserve the stored ticket types
        else v_ticket_types_before
    end;
    v_payment_currency_code := case
        -- Use the submitted currency
        when p_event ? 'payment_currency_code' then nullif(p_event->>'payment_currency_code', '')
        -- Preserve the stored currency
        else nullif(v_before.payment_currency_code, '')
    end;
    v_timezone := coalesce(
        nullif(p_event->>'timezone', ''),
        nullif(v_before.timezone, ''),
        'UTC'
    );
    v_starts_at := case
        -- Use the submitted start
        when p_event ? 'starts_at' then nullif(p_event->>'starts_at', '')::timestamp at time zone v_timezone
        -- Preserve the stored start
        else v_before.starts_at
    end;
    v_ends_at := case
        -- Use the submitted end
        when p_event ? 'ends_at' then nullif(p_event->>'ends_at', '')::timestamp at time zone v_timezone
        -- Preserve the stored end
        else v_before.ends_at
    end;

    -- Resolve the prior and proposed paid-ticketing activity states
    v_was_payment_active := v_before.published
        and (
            event_effective_ends_at(v_before) is null
            or event_effective_ends_at(v_before) > current_timestamp
        );
    v_will_payment_active := v_before.published
        and (
            coalesce(v_ends_at, v_starts_at) is null
            or coalesce(v_ends_at, v_starts_at) > current_timestamp
        );
    v_payment_became_active := not v_was_payment_active and v_will_payment_active;

    -- Compare the taxable performance context
    v_performance_context_changed :=
        p_event->>'kind_id' is distinct from v_before.event_kind_id
        or nullif(btrim(p_event->>'venue_address'), '')
            is distinct from nullif(btrim(v_before.venue_address), '')
        or nullif(btrim(p_event->>'venue_city'), '')
            is distinct from nullif(btrim(v_before.venue_city), '')
        or nullif(btrim(p_event->>'venue_country_code'), '')
            is distinct from nullif(btrim(v_before.venue_country_code), '')
        or nullif(btrim(p_event->>'venue_name'), '')
            is distinct from nullif(btrim(v_before.venue_name), '')
        or upper(nullif(btrim(
            case
                -- Use the submitted subdivision code
                when p_event ? 'venue_state_code' then p_event->>'venue_state_code'
                -- Preserve the stored subdivision code
                else v_before.venue_state_code
            end
        ), ''))
            is distinct from upper(nullif(btrim(v_before.venue_state_code), ''))
        or nullif(btrim(coalesce(p_event->>'venue_state_name', p_event->>'venue_state')), '')
            is distinct from nullif(btrim(v_before.venue_state_name), '')
        or nullif(btrim(p_event->>'venue_zip_code'), '')
            is distinct from nullif(btrim(v_before.venue_zip_code), '');

    -- Compare pricing inputs on their configuration projections so read-model
    -- fields, live inventory, ordering and timestamp spellings never register
    -- as changes
    v_pricing_configuration_changed :=
        event_discount_codes_configuration(v_discount_codes, v_discount_codes_before)
            is distinct from event_discount_codes_configuration(
                v_discount_codes_before,
                v_discount_codes_before
            )
        or v_payment_currency_code is distinct from nullif(v_before.payment_currency_code, '')
        or event_ticket_types_configuration(v_ticket_types)
            is distinct from event_ticket_types_configuration(v_ticket_types_before);

    -- Compare tax policy inputs
    v_tax_configuration_changed :=
        case
            -- Use the submitted manual tax rates
            when p_event ? 'manual_tax_rate_ids' then coalesce(p_event->'manual_tax_rate_ids', '[]'::jsonb)
            -- Preserve the stored manual tax rates
            else coalesce(to_jsonb(v_before.manual_tax_rate_ids), '[]'::jsonb)
        end
            is distinct from coalesce(to_jsonb(v_before.manual_tax_rate_ids), '[]'::jsonb)
        or case
            -- Use the submitted display behavior
            when p_event ? 'tax_behavior' then coalesce(nullif(p_event->>'tax_behavior', ''), 'inclusive')
            -- Preserve the stored display behavior
            else coalesce(nullif(v_before.tax_behavior, ''), 'inclusive')
        end
            is distinct from coalesce(v_before.tax_behavior, 'inclusive')
        or case
            -- Use the submitted tax mode
            when p_event ? 'tax_calculation_mode'
            then coalesce(nullif(p_event->>'tax_calculation_mode', ''), 'automatic')
            -- Preserve the stored tax mode
            else coalesce(nullif(v_before.tax_calculation_mode, ''), 'automatic')
        end
            is distinct from coalesce(v_before.tax_calculation_mode, 'automatic');

    -- Compare external-payment URL, instructions, and window
    v_external_configuration_changed :=
        case
            -- Use the submitted instructions
            when p_event ? 'external_payment_instructions'
            then nullif(btrim(p_event->>'external_payment_instructions'), '')
            -- Preserve the stored instructions
            else nullif(btrim(v_before.external_payment_instructions), '')
        end
            is distinct from nullif(btrim(v_before.external_payment_instructions), '')
        or case
            -- Use the submitted URL
            when p_event ? 'external_payment_url'
            then nullif(btrim(p_event->>'external_payment_url'), '')
            -- Preserve the stored URL
            else nullif(btrim(v_before.external_payment_url), '')
        end
            is distinct from nullif(btrim(v_before.external_payment_url), '')
        or case
            -- Use the submitted window
            when p_event ? 'external_payment_window_hours'
            then nullif(p_event->>'external_payment_window_hours', '')::int
            -- Preserve the stored window
            else v_before.external_payment_window_hours
        end
            is distinct from v_before.external_payment_window_hours;

    -- Report changes that can govern a paid purchase
    return is_event_ticketing_payload_paid_capable(v_ticket_types) and (
        v_external_configuration_changed
        or v_payment_became_active
        or v_performance_context_changed
        or v_pricing_configuration_changed
        or v_tax_configuration_changed
    );
end;
$$ language plpgsql stable;
