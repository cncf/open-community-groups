-- Resolves the event columns, ticket types and discount codes written by
-- add_event and update_event from a submitted payload. Every key is parsed and
-- normalized once here (trimmed optional text, upper-cased codes, timestamps
-- in the event timezone, boolean and array defaults). Keys that the dashboard
-- may omit from an update payload are merged over the prior row when the
-- payload lacks them; without a prior row (add) their defaults apply and a
-- missing ticket configuration falls back to a single public tier. Payment
-- rail selection is delegated to resolve_event_payment_rail. Columns owned by
-- the callers (identifiers, slug, audit and sync state) stay null.
create or replace function resolve_event_payload(
    p_event jsonb,
    p_before event,
    p_group_external_ready boolean
)
returns table (
    discount_codes jsonb,
    external_mode boolean,
    resolved event,
    ticket_types jsonb
) as $$
declare
    v_adding boolean := p_before.event_id is null;
    v_discount_codes jsonb;
    v_rail record;
    v_resolved event;
    v_ticket_types jsonb;
    v_timezone text := p_event->>'timezone';
begin
    -- Merge the ticket configuration over the prior rows when the payload omits it
    v_discount_codes := case
        -- Use the submitted discount codes
        when p_event ? 'discount_codes' then nullif(p_event->'discount_codes', 'null'::jsonb)
        -- Preserve the stored discount codes of an existing event
        when not v_adding then list_event_discount_codes(p_before.event_id)
    end;
    v_ticket_types := case
        -- Use the submitted ticket types
        when p_event ? 'ticket_types' then nullif(p_event->'ticket_types', 'null'::jsonb)
        -- Preserve the stored ticket types of an existing event
        when not v_adding then list_event_ticket_types(p_before.event_id)
    end;

    -- Give new events without ticket types a single public tier
    if v_adding then
        v_ticket_types := coalesce(
            v_ticket_types,
            jsonb_build_array(jsonb_build_object(
                'active', true,
                'availability', 'public',
                'event_ticket_type_id', gen_random_uuid(),
                'order', 1,
                'price_windows', jsonb_build_array(jsonb_build_object(
                    'amount_minor', 0,
                    'event_ticket_price_window_id', gen_random_uuid()
                )),
                'seats_total', 500,
                'title', 'General Admission'
            ))
        );
    end if;

    -- Parse the columns the payload always carries
    v_resolved.attendee_approval_required := coalesce((p_event->>'attendee_approval_required')::boolean, false);
    v_resolved.banner_mobile_url := nullif(p_event->>'banner_mobile_url', '');
    v_resolved.banner_url := nullif(p_event->>'banner_url', '');
    v_resolved.capacity := get_event_ticket_capacity(v_ticket_types);
    v_resolved.cfs_description := nullif(p_event->>'cfs_description', '');
    v_resolved.cfs_enabled := (p_event->>'cfs_enabled')::boolean;
    v_resolved.cfs_ends_at := (p_event->>'cfs_ends_at')::timestamp at time zone v_timezone;
    v_resolved.cfs_starts_at := (p_event->>'cfs_starts_at')::timestamp at time zone v_timezone;
    v_resolved.description := p_event->>'description';
    v_resolved.description_short := nullif(p_event->>'description_short', '');
    v_resolved.ends_at := (p_event->>'ends_at')::timestamp at time zone v_timezone;
    v_resolved.event_category_id := (p_event->>'category_id')::uuid;
    v_resolved.event_kind_id := p_event->>'kind_id';
    v_resolved.event_reminder_enabled := coalesce((p_event->>'event_reminder_enabled')::boolean, true);
    v_resolved.location := jsonb_geography_point(p_event);
    v_resolved.logo_url := nullif(p_event->>'logo_url', '');
    v_resolved.luma_url := nullif(p_event->>'luma_url', '');
    v_resolved.meeting_hosts := jsonb_text_array(p_event->'meeting_hosts');
    v_resolved.meeting_join_instructions := nullif(p_event->>'meeting_join_instructions', '');
    v_resolved.meeting_join_url := nullif(p_event->>'meeting_join_url', '');
    v_resolved.meeting_provider_id := nullif(p_event->>'meeting_provider_id', '');
    v_resolved.meeting_recording_requested := coalesce((p_event->>'meeting_recording_requested')::boolean, true);
    v_resolved.meeting_recording_url := nullif(p_event->>'meeting_recording_url', '');
    v_resolved.meeting_requested := (p_event->>'meeting_requested')::boolean;
    v_resolved.meetup_url := nullif(p_event->>'meetup_url', '');
    v_resolved.name := p_event->>'name';
    v_resolved.photos_urls := jsonb_text_array(p_event->'photos_urls');
    v_resolved.registration_ends_at := (p_event->>'registration_ends_at')::timestamp at time zone v_timezone;
    v_resolved.registration_starts_at := (p_event->>'registration_starts_at')::timestamp at time zone v_timezone;
    v_resolved.starts_at := (p_event->>'starts_at')::timestamp at time zone v_timezone;
    v_resolved.tags := jsonb_text_array(p_event->'tags');
    v_resolved.test_event := coalesce((p_event->>'test_event')::boolean, false);
    v_resolved.timezone := v_timezone;
    v_resolved.venue_address := nullif(btrim(p_event->>'venue_address'), '');
    v_resolved.venue_city := nullif(btrim(p_event->>'venue_city'), '');
    v_resolved.venue_country_code := upper(nullif(btrim(p_event->>'venue_country_code'), ''));
    v_resolved.venue_country_name := nullif(btrim(p_event->>'venue_country_name'), '');
    v_resolved.venue_name := nullif(btrim(p_event->>'venue_name'), '');
    v_resolved.venue_state_name := nullif(
        btrim(coalesce(p_event->>'venue_state_name', p_event->>'venue_state')),
        ''
    );
    v_resolved.venue_zip_code := nullif(btrim(p_event->>'venue_zip_code'), '');
    v_resolved.waitlist_enabled := coalesce((p_event->>'waitlist_enabled')::boolean, false);

    -- Merge the columns a partial payload may omit over the prior row
    v_resolved.external_payment_instructions := case
        -- Use the submitted instructions
        when p_event ? 'external_payment_instructions'
        then nullif(btrim(p_event->>'external_payment_instructions'), '')
        -- Preserve the stored instructions
        else nullif(btrim(p_before.external_payment_instructions), '')
    end;
    v_resolved.external_payment_url := case
        -- Use the submitted URL
        when p_event ? 'external_payment_url'
        then nullif(btrim(p_event->>'external_payment_url'), '')
        -- Preserve the stored URL
        else nullif(btrim(p_before.external_payment_url), '')
    end;
    v_resolved.external_payment_window_hours := case
        -- Use the submitted window
        when p_event ? 'external_payment_window_hours'
        then nullif(p_event->>'external_payment_window_hours', '')::int
        -- Preserve the stored window
        else p_before.external_payment_window_hours
    end;
    v_resolved.manual_tax_rate_ids := case
        -- Use the submitted manual tax rates
        when p_event ? 'manual_tax_rate_ids'
        then coalesce(jsonb_text_array(p_event->'manual_tax_rate_ids'), '{}'::text[])
        -- Preserve the stored manual tax rates
        else coalesce(p_before.manual_tax_rate_ids, '{}'::text[])
    end;
    v_resolved.meeting_recording_published := coalesce(
        (p_event->>'meeting_recording_published')::boolean,
        p_before.meeting_recording_published,
        false
    );
    v_resolved.payment_currency_code := case
        -- Use the submitted currency
        when p_event ? 'payment_currency_code'
        then nullif(p_event->>'payment_currency_code', '')
        -- Preserve the stored currency
        else nullif(p_before.payment_currency_code, '')
    end;
    v_resolved.registration_questions := case
        -- Use the submitted registration questions
        when p_event ? 'registration_questions'
        then coalesce(p_event->'registration_questions', '[]'::jsonb)
        -- Preserve the stored registration questions
        else coalesce(p_before.registration_questions, '[]'::jsonb)
    end;
    v_resolved.tax_calculation_mode := case
        -- Use the submitted tax mode
        when p_event ? 'tax_calculation_mode'
        then coalesce(nullif(p_event->>'tax_calculation_mode', ''), 'automatic')
        -- Preserve the stored tax mode
        else coalesce(nullif(p_before.tax_calculation_mode, ''), 'automatic')
    end;
    v_resolved.tax_behavior := case
        -- Events that collect no tax display inclusive prices
        when v_resolved.tax_calculation_mode = 'none' then 'inclusive'
        -- Use the submitted display behavior
        when p_event ? 'tax_behavior'
        then coalesce(nullif(p_event->>'tax_behavior', ''), 'inclusive')
        -- Preserve the stored display behavior
        else coalesce(nullif(p_before.tax_behavior, ''), 'inclusive')
    end;
    v_resolved.venue_state_code := case
        -- Apply an explicitly submitted subdivision code
        when p_event ? 'venue_state_code'
        then upper(nullif(btrim(p_event->>'venue_state_code'), ''))
        -- Clear a code invalidated by a legacy country or subdivision edit
        when v_resolved.venue_country_code
                is distinct from upper(nullif(btrim(p_before.venue_country_code), ''))
            or (
                (p_event ? 'venue_state_name' or p_event ? 'venue_state')
                and v_resolved.venue_state_name
                    is distinct from nullif(btrim(p_before.venue_state_name), '')
            )
        then null
        -- Preserve the code while the deferred frontend omits this field
        else p_before.venue_state_code
    end;

    -- Select the payment rail and normalize the tax and external fields for it
    select *
    into v_rail
    from resolve_event_payment_rail(v_resolved, v_ticket_types, p_group_external_ready);

    -- Return the resolved payload
    return query select v_discount_codes, v_rail.external_mode, v_rail.resolved, v_ticket_types;
end;
$$ language plpgsql;
