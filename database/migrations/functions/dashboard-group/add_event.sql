-- add_event adds a new event to the database.
create or replace function add_event(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event jsonb,
    p_cfg_max_participants jsonb default null,
    p_configured_provider text default null
)
returns uuid as $$
declare
    v_discount_codes jsonb := nullif(p_event->'discount_codes', 'null'::jsonb);
    v_event_attendee_approval_required boolean := coalesce((p_event->>'attendee_approval_required')::boolean, false);
    v_event_id uuid;
    v_max_retries int := 10;
    v_payment_currency_code text := nullif(p_event->>'payment_currency_code', '');
    v_payment_recipient jsonb;
    v_payment_validation jsonb := p_event->'_payment_validation';
    v_retries int := 0;
    v_slug text;
    v_ticket_types jsonb := coalesce(
        nullif(p_event->'ticket_types', 'null'::jsonb),
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
    v_ticket_capacity int := get_event_ticket_capacity(v_ticket_types);
begin
    -- Validate registration questions before writing the event
    perform validate_questionnaire_questions_payload(coalesce(p_event->'registration_questions', '[]'::jsonb));

    -- Lock group payment state through paid-capable ticket validation and insertion
    select g.payment_recipient into v_payment_recipient
    from "group" g
    where g.group_id = p_group_id
    for update of g;

    -- Bind provider validation to the recipient protected by the group lock
    if p_configured_provider is not null
       and is_event_ticketing_payload_paid_capable(v_ticket_types)
       and (
           v_payment_validation is null
           or not (v_payment_validation ? 'expected_payment_recipient')
           or not (v_payment_validation ? 'validated_payment_recipient')
           or not (v_payment_validation ? 'require_automatic_tax')
           or v_payment_recipient is distinct from nullif(
               v_payment_validation->'expected_payment_recipient',
               'null'::jsonb
           )
           or v_payment_recipient is distinct from nullif(
               v_payment_validation->'validated_payment_recipient',
               'null'::jsonb
           )
           or (
               coalesce(
                   nullif(p_event->>'tax_calculation_mode', ''),
                   'automatic'
               ) = 'automatic'
               and not (v_payment_validation->>'require_automatic_tax')::boolean
           )
       ) then
        raise exception 'payment configuration changed during provider validation';
    end if;

    -- Validate enrollment and ticketing payload rules
    perform validate_event_enrollment_payload(
        v_event_attendee_approval_required,
        coalesce((p_event->>'waitlist_enabled')::boolean, false)
    );

    perform validate_event_ticketing_payload(
        p_configured_provider,
        v_discount_codes,
        v_payment_currency_code,
        v_payment_recipient,
        v_ticket_types,
        true,
        null,
        p_event
    );

    -- Validate add-specific event and session date rules
    perform validate_add_event_dates(p_event);

    -- Validate capacity and CFS label rules
    perform validate_event_capacity(
        p_event,
        p_cfg_max_participants,
        p_effective_capacity => v_ticket_capacity
    );
    perform validate_event_cfs_labels_payload(p_event->'cfs_labels');

    -- Insert event with unique slug generation and collision retry
    loop
        v_slug := generate_slug(7);

        begin
            insert into event (
                group_id,
                name,
                slug,
                description,
                test_event,
                timezone,
                event_category_id,
                event_kind_id,

                attendee_approval_required,
                banner_mobile_url,
                banner_url,
                capacity,
                cfs_description,
                cfs_enabled,
                cfs_ends_at,
                cfs_starts_at,
                created_by,
                description_short,
                ends_at,
                event_reminder_enabled,
                location,
                logo_url,
                luma_url,
                meeting_hosts,
                meeting_in_sync,
                meeting_join_instructions,
                meeting_join_url,
                meeting_provider_id,
                meeting_recording_published,
                meeting_recording_requested,
                meeting_recording_url,
                meeting_requested,
                meetup_url,
                payment_currency_code,
                photos_urls,
                registration_ends_at,
                registration_questions,
                registration_starts_at,
                starts_at,
                tags,
                tax_behavior,
                tax_calculation_mode,
                venue_address,
                venue_city,
                venue_country_code,
                venue_country_name,
                venue_name,
                venue_state,
                venue_zip_code,
                waitlist_enabled
            ) values (
                p_group_id,
                p_event->>'name',
                v_slug,
                p_event->>'description',
                coalesce((p_event->>'test_event')::boolean, false),
                p_event->>'timezone',
                (p_event->>'category_id')::uuid,
                p_event->>'kind_id',

                v_event_attendee_approval_required,
                nullif(p_event->>'banner_mobile_url', ''),
                nullif(p_event->>'banner_url', ''),
                v_ticket_capacity,
                nullif(p_event->>'cfs_description', ''),
                (p_event->>'cfs_enabled')::boolean,
                (p_event->>'cfs_ends_at')::timestamp at time zone (p_event->>'timezone'),
                (p_event->>'cfs_starts_at')::timestamp at time zone (p_event->>'timezone'),
                p_actor_user_id,
                nullif(p_event->>'description_short', ''),
                (p_event->>'ends_at')::timestamp at time zone (p_event->>'timezone'),
                coalesce((p_event->>'event_reminder_enabled')::boolean, true),
                jsonb_geography_point(p_event),
                nullif(p_event->>'logo_url', ''),
                nullif(p_event->>'luma_url', ''),
                jsonb_text_array(p_event->'meeting_hosts'),
                case
                    when (p_event->>'meeting_requested')::boolean = true then false
                    else null
                end,
                nullif(p_event->>'meeting_join_instructions', ''),
                nullif(p_event->>'meeting_join_url', ''),
                nullif(p_event->>'meeting_provider_id', ''),
                coalesce((p_event->>'meeting_recording_published')::boolean, false),
                coalesce((p_event->>'meeting_recording_requested')::boolean, true),
                nullif(p_event->>'meeting_recording_url', ''),
                (p_event->>'meeting_requested')::boolean,
                nullif(p_event->>'meetup_url', ''),
                v_payment_currency_code,
                jsonb_text_array(p_event->'photos_urls'),
                (p_event->>'registration_ends_at')::timestamp at time zone (p_event->>'timezone'),
                coalesce(p_event->'registration_questions', '[]'::jsonb),
                (p_event->>'registration_starts_at')::timestamp at time zone (p_event->>'timezone'),
                (p_event->>'starts_at')::timestamp at time zone (p_event->>'timezone'),
                jsonb_text_array(p_event->'tags'),
                coalesce(nullif(p_event->>'tax_behavior', ''), 'inclusive'),
                coalesce(nullif(p_event->>'tax_calculation_mode', ''), 'automatic'),
                nullif(btrim(p_event->>'venue_address'), ''),
                nullif(btrim(p_event->>'venue_city'), ''),
                nullif(btrim(p_event->>'venue_country_code'), ''),
                nullif(btrim(p_event->>'venue_country_name'), ''),
                nullif(btrim(p_event->>'venue_name'), ''),
                nullif(btrim(p_event->>'venue_state'), ''),
                nullif(btrim(p_event->>'venue_zip_code'), ''),
                coalesce((p_event->>'waitlist_enabled')::boolean, false)
            )
            returning event_id into v_event_id;

            exit; -- Success, exit the loop
        exception when unique_violation then
            v_retries := v_retries + 1;
            if v_retries >= v_max_retries then
                raise exception 'failed to generate unique slug after % attempts', v_max_retries;
            end if;
        end;
    end loop;

    -- Snapshot current accepted group organizers for historical attribution
    insert into event_organizer (event_id, user_id, "order")
    select v_event_id, gt.user_id, gt."order"
    from group_team gt
    where gt.group_id = p_group_id
    and gt.accepted = true;

    -- Insert ticketing data after creating the event row
    perform sync_event_discount_codes(v_event_id, v_discount_codes);
    perform sync_event_ticket_types(v_event_id, v_ticket_types);

    -- Insert CFS labels
    perform sync_event_cfs_labels(v_event_id, p_event->'cfs_labels');

    -- Insert event hosts, speakers, and sponsors
    perform sync_event_hosts_speakers_sponsors(v_event_id, p_event);

    -- Insert sessions and speakers
    perform sync_event_sessions(v_event_id, p_event, '{}'::jsonb);

    -- Track the created event
    perform insert_audit_log(
        'event_added',
        p_actor_user_id,
        'event',
        v_event_id,
        (select community_id from "group" where group_id = p_group_id),
        p_group_id,
        v_event_id
    );

    return v_event_id;
end;
$$ language plpgsql;
