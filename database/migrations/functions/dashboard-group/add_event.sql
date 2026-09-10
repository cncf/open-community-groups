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
    v_event event;
    v_event_id uuid;
    v_group_country_code text;
    v_group_external_ready boolean;
    v_max_retries int := 10;
    v_payload record;
    v_payment_recipient jsonb;
    v_retries int := 0;
    v_slug text;
begin
    -- Validate registration questions before writing the event
    perform validate_questionnaire_questions_payload(coalesce(p_event->'registration_questions', '[]'::jsonb));

    -- Lock group payment state through paid-capable ticket validation and insertion
    select
        g.country_code,
        is_group_external_payments_ready(g.group_id),
        g.payment_recipient
    into
        v_group_country_code,
        v_group_external_ready,
        v_payment_recipient
    from "group" g
    where g.group_id = p_group_id
    for update of g;

    -- Resolve the event columns, ticket configuration and payment rail from the payload
    select *
    into v_payload
    from resolve_event_payload(p_event, null::event, v_group_external_ready);
    v_event := v_payload.resolved;

    -- Bind provider validation to the recipient protected by the group lock
    if p_configured_provider is not null
       and is_event_ticketing_payload_paid_capable(v_payload.ticket_types)
       and not v_payload.external_mode then
        perform validate_event_payment_validation(
            p_event,
            v_payment_recipient,
            v_event.manual_tax_rate_ids,
            v_event.tax_behavior,
            v_event.tax_calculation_mode
        );
    end if;

    -- Validate enrollment and ticketing payload rules
    perform validate_event_enrollment_payload(
        v_event.attendee_approval_required,
        v_event.waitlist_enabled
    );

    perform validate_event_ticketing_payload(
        p_configured_provider,
        v_payload.discount_codes,
        v_event.payment_currency_code,
        v_payment_recipient,
        v_payload.ticket_types,
        true,
        null,
        p_event || jsonb_build_object(
            'external_mode', v_payload.external_mode,
            'external_payment_url', v_event.external_payment_url,
            'external_payment_window_hours', v_event.external_payment_window_hours,
            'group_country_code', v_group_country_code,
            'manual_tax_rate_ids', to_jsonb(v_event.manual_tax_rate_ids),
            'tax_calculation_mode', v_event.tax_calculation_mode
        )
    );

    -- Validate add-specific event and session date rules
    perform validate_add_event_dates(p_event);

    -- Validate capacity and CFS label rules
    perform validate_event_capacity(
        p_event,
        p_cfg_max_participants,
        p_effective_capacity => v_event.capacity
    );
    perform validate_event_cfs_labels_payload(p_event->'cfs_labels');

    -- Insert event with unique slug generation and collision retry
    loop
        v_slug := generate_slug(7);

        -- Attempt the insert with the candidate slug
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
                external_payment_instructions,
                external_payment_url,
                external_payment_window_hours,
                location,
                logo_url,
                luma_url,
                manual_tax_rate_ids,
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
                venue_state_code,
                venue_state_name,
                venue_zip_code,
                waitlist_enabled
            ) values (
                p_group_id,
                v_event.name,
                v_slug,
                v_event.description,
                v_event.test_event,
                v_event.timezone,
                v_event.event_category_id,
                v_event.event_kind_id,

                v_event.attendee_approval_required,
                v_event.banner_mobile_url,
                v_event.banner_url,
                v_event.capacity,
                v_event.cfs_description,
                v_event.cfs_enabled,
                v_event.cfs_ends_at,
                v_event.cfs_starts_at,
                p_actor_user_id,
                v_event.description_short,
                v_event.ends_at,
                v_event.event_reminder_enabled,
                v_event.external_payment_instructions,
                v_event.external_payment_url,
                v_event.external_payment_window_hours,
                v_event.location,
                v_event.logo_url,
                v_event.luma_url,
                v_event.manual_tax_rate_ids,
                v_event.meeting_hosts,
                case
                    -- Start requested meetings out of sync so provisioning runs
                    when v_event.meeting_requested = true then false
                    -- Leave unrequested meetings without sync state
                    else null
                end,
                v_event.meeting_join_instructions,
                v_event.meeting_join_url,
                v_event.meeting_provider_id,
                v_event.meeting_recording_published,
                v_event.meeting_recording_requested,
                v_event.meeting_recording_url,
                v_event.meeting_requested,
                v_event.meetup_url,
                v_event.payment_currency_code,
                v_event.photos_urls,
                v_event.registration_ends_at,
                v_event.registration_questions,
                v_event.registration_starts_at,
                v_event.starts_at,
                v_event.tags,
                v_event.tax_behavior,
                v_event.tax_calculation_mode,
                v_event.venue_address,
                v_event.venue_city,
                v_event.venue_country_code,
                v_event.venue_country_name,
                v_event.venue_name,
                v_event.venue_state_code,
                v_event.venue_state_name,
                v_event.venue_zip_code,
                v_event.waitlist_enabled
            )
            returning event_id into v_event_id;

            -- Stop retrying once the insert succeeds
            exit;
        exception
            -- Retry slug collisions up to the configured limit
            when unique_violation then
                v_retries := v_retries + 1;

                -- Give up after exhausting the retry budget
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
    perform sync_event_discount_codes(v_event_id, v_payload.discount_codes);
    perform sync_event_ticket_types(v_event_id, v_payload.ticket_types);

    -- Insert CFS labels
    perform sync_event_cfs_labels(v_event_id, p_event->'cfs_labels');

    -- Insert event hosts, speakers, and sponsors
    perform sync_event_hosts_speakers_sponsors(v_event_id, p_event);

    -- Insert sessions and speakers
    perform sync_event_sessions(v_event_id, p_event, null::event);

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
