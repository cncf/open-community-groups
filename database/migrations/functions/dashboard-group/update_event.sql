-- update_event updates an existing event in the database.
create or replace function update_event(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_event jsonb,
    p_cfg_max_participants jsonb default null,
    p_configured_provider text default null
)
returns boolean as $$
declare
    v_community_id uuid;
    v_discount_codes jsonb;
    v_effective_capacity int;
    v_event_attendee_approval_required boolean := coalesce((p_event->>'attendee_approval_required')::boolean, false);
    v_event_before jsonb;
    v_event_location geography;
    v_event_meeting_hosts text[];
    v_event_photos_urls text[];
    v_event_reminder_enabled boolean := coalesce((p_event->>'event_reminder_enabled')::boolean, true);
    v_event_tags text[];
    v_event_waitlist_enabled boolean := coalesce((p_event->>'waitlist_enabled')::boolean, false);
    v_external_mode boolean := false;
    v_external_payment_instructions text;
    v_external_payment_url text;
    v_external_payment_window_hours int;
    v_group_country_code text;
    v_group_external_ready boolean := false;
    v_has_pending_invitation_requests boolean;
    v_has_waitlist_entries boolean;
    v_is_paid_capable boolean;
    v_is_test_event boolean;
    v_manual_tax_rate_ids text[];
    v_new_ends_at timestamptz;
    v_new_starts_at timestamptz;
    v_payment_currency_code text;
    v_payment_recipient jsonb;
    v_payment_validation jsonb := p_event->'_payment_validation';
    v_registration_ends_at timestamptz;
    v_registration_questions jsonb;
    v_registration_starts_at timestamptz;
    v_tax_behavior text;
    v_tax_calculation_mode text;
    v_ticket_capacity int;
    v_ticketing_configuration_changed boolean;
    v_ticket_types jsonb;
    v_timezone text := p_event->>'timezone';
    v_was_paid_capable boolean;
    v_was_test_event boolean;
begin
    -- Lock the group payment state before the event so recipient changes and
    -- paid ticket updates cannot invalidate each other
    select
        g.community_id,
        g.country_code,
        is_group_external_payments_ready(g.group_id),
        g.payment_recipient
    into
        v_community_id,
        v_group_country_code,
        v_group_external_ready,
        v_payment_recipient
    from "group" g
    where g.group_id = p_group_id
    and g.deleted = false
    for update;

    -- Reject missing or inactive groups before loading the event
    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Load the locked event state used by the update flow
    select get_event_full(v_community_id, p_group_id, p_event_id)::jsonb
    into v_event_before
    from event e
    where e.group_id = p_group_id
    and e.event_id = p_event_id
    and e.deleted = false
    and e.canceled = false
    for update of e;

    -- Reject missing or inactive events before resolving the update
    if v_event_before is null then
        raise exception 'event not found or inactive';
    end if;

    -- Parse payload values used across the update flow
    v_event_location := jsonb_geography_point(p_event);
    v_event_meeting_hosts := jsonb_text_array(p_event->'meeting_hosts');
    v_event_photos_urls := jsonb_text_array(p_event->'photos_urls');
    v_event_tags := jsonb_text_array(p_event->'tags');
    v_is_test_event := coalesce((p_event->>'test_event')::boolean, false);

    -- Resolve ticketing values and the effective event capacity
    v_discount_codes := case
        when p_event ? 'discount_codes'
        then nullif(p_event->'discount_codes', 'null'::jsonb)
        else v_event_before->'discount_codes'
    end;
    v_ticket_types := case
        when p_event ? 'ticket_types'
        then nullif(p_event->'ticket_types', 'null'::jsonb)
        else v_event_before->'ticket_types'
    end;
    v_is_paid_capable := is_event_ticketing_payload_paid_capable(v_ticket_types);
    v_manual_tax_rate_ids := case
        when p_event ? 'manual_tax_rate_ids'
        then coalesce(jsonb_text_array(p_event->'manual_tax_rate_ids'), '{}'::text[])
        else coalesce(jsonb_text_array(v_event_before->'manual_tax_rate_ids'), '{}'::text[])
    end;
    v_ticket_capacity := get_event_ticket_capacity(v_ticket_types);
    v_tax_calculation_mode := case
        when p_event ? 'tax_calculation_mode'
        then coalesce(nullif(p_event->>'tax_calculation_mode', ''), 'automatic')
        else coalesce(nullif(v_event_before->>'tax_calculation_mode', ''), 'automatic')
    end;
    v_tax_behavior := case
        when v_tax_calculation_mode = 'none' then 'inclusive'
        when p_event ? 'tax_behavior'
        then coalesce(nullif(p_event->>'tax_behavior', ''), 'inclusive')
        else coalesce(nullif(v_event_before->>'tax_behavior', ''), 'inclusive')
    end;
    v_effective_capacity := v_ticket_capacity;
    v_payment_currency_code := case
        when p_event ? 'payment_currency_code'
        then nullif(p_event->>'payment_currency_code', '')
        else nullif(v_event_before->>'payment_currency_code', '')
    end;
    v_was_paid_capable := is_event_ticketing_payload_paid_capable(v_event_before->'ticket_types');
    v_was_test_event := coalesce((v_event_before->>'test_event')::boolean, false);
    v_external_payment_instructions := case
        when p_event ? 'external_payment_instructions'
        then nullif(btrim(p_event->>'external_payment_instructions'), '')
        else nullif(btrim(v_event_before->>'external_payment_instructions'), '')
    end;
    v_external_payment_url := case
        when p_event ? 'external_payment_url'
        then nullif(btrim(p_event->>'external_payment_url'), '')
        else nullif(btrim(v_event_before->>'external_payment_url'), '')
    end;
    v_external_payment_window_hours := case
        when p_event ? 'external_payment_window_hours'
        then nullif(p_event->>'external_payment_window_hours', '')::int
        else nullif(v_event_before->>'external_payment_window_hours', '')::int
    end;

    -- Reject any external URL while the group cannot collect externally
    if v_external_payment_url is not null and not v_group_external_ready then
        raise exception 'external payments are not available for this event';
    end if;

    -- Use the external rail only while the group is eligible right now
    v_external_mode := v_is_paid_capable and v_group_external_ready;

    -- Normalize external paid events onto organizer-managed tax
    if v_external_mode then
        v_manual_tax_rate_ids := '{}'::text[];
        v_tax_behavior := 'inclusive';
        v_tax_calculation_mode := 'none';

    -- Clear leftover external fields only when the event is leaving that rail
    else
        v_external_payment_instructions := null;
        v_external_payment_url := null;
        v_external_payment_window_hours := null;
    end if;

    v_ticketing_configuration_changed := event_ticketing_configuration_changed(
        v_event_before,
        p_event || jsonb_build_object(
            'external_payment_instructions', v_external_payment_instructions,
            'external_payment_url', v_external_payment_url,
            'external_payment_window_hours', v_external_payment_window_hours
        )
    );

    -- Bind provider validation to the recipient protected by the group lock
    if p_configured_provider is not null
       and v_is_paid_capable
       and v_ticketing_configuration_changed
       and not v_external_mode
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
           or (
               v_tax_calculation_mode = 'manual'
               and (
                   v_payment_validation->'manual_tax_rate_ids'
                       is distinct from to_jsonb(v_manual_tax_rate_ids)
                   or v_payment_validation->>'tax_behavior' is distinct from
                       v_tax_behavior
                   or v_payment_validation->>'tax_calculation_mode' <> 'manual'
               )
           )
       ) then
        raise exception 'payment configuration changed during provider validation';
    end if;

    -- Resolve registration question defaults
    v_registration_questions := case
        -- Use explicitly submitted registration questions
        when p_event ? 'registration_questions'
        then coalesce(p_event->'registration_questions', '[]'::jsonb)
        -- Preserve registration questions omitted from a partial payload
        else coalesce(v_event_before->'registration_questions', '[]'::jsonb)
    end;

    -- Validate registration questions and prevent changing definitions with live user state
    perform validate_questionnaire_questions_payload(v_registration_questions);

    -- Protect submitted questionnaire answers and active checkout holds
    if v_registration_questions <> coalesce(v_event_before->'registration_questions', '[]'::jsonb) then
        -- Reject changes after attendees submit answers
        if questionnaire_answers_exist_for_event(p_event_id) then
            raise exception 'registration questions cannot be changed after attendees have submitted answers';
        end if;

        -- Reject changes while pending purchases hold questionnaire state
        if exists (
            select 1
            from event_purchase ep
            where ep.event_id = p_event_id
            and ep.status = 'pending'
            and ep.hold_expires_at > current_timestamp
        ) then
            raise exception 'registration questions cannot be changed while checkout holds are active';
        end if;
    end if;

    -- Load current enrollment state required by approval guards
    v_has_pending_invitation_requests := exists(
        select 1
        from event_invitation_request
        where event_id = p_event_id
        and status = 'pending'
    );
    v_has_waitlist_entries := exists(
        select 1
        from event_waitlist
        where event_id = p_event_id
    );

    -- Clear stale currency when the last positive price is removed without discounts
    if not is_event_ticketing_payload_paid_capable(v_ticket_types)
       and v_discount_codes is null then
        v_payment_currency_code := null;
    end if;

    -- Enforce attendee approval transition rules
    if v_event_attendee_approval_required = false and v_has_pending_invitation_requests then
        raise exception 'approval-required events with pending invitation requests cannot disable approval';
    end if;

    -- Block approval-required attendance while queued users exist
    if v_event_attendee_approval_required = true and v_has_waitlist_entries then
        raise exception 'approval-required events cannot have existing waitlist entries';
    end if;

    -- Validate enrollment and ticketing payload rules
    perform validate_event_enrollment_payload(
        v_event_attendee_approval_required,
        v_event_waitlist_enabled
    );

    perform validate_event_ticketing_payload(
        p_configured_provider,
        v_discount_codes,
        v_payment_currency_code,
        v_payment_recipient,
        v_ticket_types,
        false,
        p_event_id,
        p_event || jsonb_build_object(
            'external_mode', v_external_mode,
            'external_payment_url', v_external_payment_url,
            'external_payment_window_hours', v_external_payment_window_hours,
            'group_country_code', v_group_country_code,
            'manual_tax_rate_ids', to_jsonb(v_manual_tax_rate_ids),
            'tax_calculation_mode', v_tax_calculation_mode
        )
    );

    -- Parse event timestamps once for validation and row updates
    -- Resolve the submitted event end time
    if p_event->>'ends_at' is not null then
        v_new_ends_at := (p_event->>'ends_at')::timestamp at time zone v_timezone;
    end if;

    -- Resolve the submitted event start time
    if p_event->>'starts_at' is not null then
        v_new_starts_at := (p_event->>'starts_at')::timestamp at time zone v_timezone;
    end if;

    -- Resolve the submitted registration end time
    if p_event->>'registration_ends_at' is not null then
        v_registration_ends_at := (p_event->>'registration_ends_at')::timestamp at time zone v_timezone;
    end if;

    -- Resolve the submitted registration start time
    if p_event->>'registration_starts_at' is not null then
        v_registration_starts_at := (p_event->>'registration_starts_at')::timestamp at time zone v_timezone;
    end if;

    -- Validate update-specific event and session date rules
    perform validate_update_event_dates(p_event, v_event_before);

    -- Validate capacity
    perform validate_event_capacity(
        p_event,
        p_cfg_max_participants,
        p_existing_event_id => p_event_id,
        p_effective_capacity => v_effective_capacity
    );

    -- Validate CFS labels rules
    perform validate_event_cfs_labels_payload(p_event->'cfs_labels');

    -- Update event
    update event set
        name = p_event->>'name',
        description = p_event->>'description',
        test_event = v_is_test_event,
        timezone = p_event->>'timezone',
        event_category_id = (p_event->>'category_id')::uuid,
        event_kind_id = p_event->>'kind_id',

        attendee_approval_required = v_event_attendee_approval_required,
        banner_mobile_url = nullif(p_event->>'banner_mobile_url', ''),
        banner_url = nullif(p_event->>'banner_url', ''),
        cfs_description = nullif(p_event->>'cfs_description', ''),
        cfs_enabled = (p_event->>'cfs_enabled')::boolean,
        cfs_ends_at = (p_event->>'cfs_ends_at')::timestamp at time zone v_timezone,
        cfs_starts_at = (p_event->>'cfs_starts_at')::timestamp at time zone v_timezone,
        description_short = nullif(p_event->>'description_short', ''),
        ends_at = v_new_ends_at,
        event_reminder_enabled = v_event_reminder_enabled,
        -- Mark reminder as evaluated when update moves start time inside the 24-hour window
        event_reminder_evaluated_for_starts_at = case
            -- Record the newly eligible reminder schedule
            when v_event_reminder_enabled = true
                 and event_reminder_sent_at is null
                 and starts_at is distinct from v_new_starts_at
                 and (
                     starts_at is null
                     or starts_at <= current_timestamp
                     or starts_at > current_timestamp + interval '24 hours'
                 )
                 and v_new_starts_at is not null
                 and v_new_starts_at > current_timestamp
                 and v_new_starts_at <= current_timestamp + interval '24 hours'
            then v_new_starts_at
            -- Preserve the prior reminder evaluation schedule
            else event_reminder_evaluated_for_starts_at
        end,
        location = v_event_location,
        logo_url = nullif(p_event->>'logo_url', ''),
        luma_url = nullif(p_event->>'luma_url', ''),
        external_payment_instructions = v_external_payment_instructions,
        external_payment_url = v_external_payment_url,
        external_payment_window_hours = v_external_payment_window_hours,
        manual_tax_rate_ids = v_manual_tax_rate_ids,
        meeting_hosts = v_event_meeting_hosts,
        meeting_in_sync = case
            -- Preserve pending meeting deletion work
            when (v_event_before->>'meeting_in_sync')::boolean = false
                 and (p_event->>'meeting_requested')::boolean is distinct from false
            then false
            -- Recompute meeting synchronization for other updates
            else is_event_meeting_in_sync(v_event_before, p_event)
        end,
        meeting_join_instructions = nullif(p_event->>'meeting_join_instructions', ''),
        meeting_join_url = nullif(p_event->>'meeting_join_url', ''),
        meeting_provider_id = p_event->>'meeting_provider_id',
        meeting_recording_published = coalesce(
            (p_event->>'meeting_recording_published')::boolean,
            (v_event_before->>'meeting_recording_published')::boolean,
            false
        ),
        meeting_recording_requested = coalesce((p_event->>'meeting_recording_requested')::boolean, true),
        meeting_recording_url = nullif(p_event->>'meeting_recording_url', ''),
        meeting_requested = (p_event->>'meeting_requested')::boolean,
        meetup_url = nullif(p_event->>'meetup_url', ''),
        payment_currency_code = v_payment_currency_code,
        photos_urls = v_event_photos_urls,
        registration_ends_at = v_registration_ends_at,
        registration_questions = v_registration_questions,
        registration_starts_at = v_registration_starts_at,
        starts_at = v_new_starts_at,
        tags = v_event_tags,
        tax_behavior = v_tax_behavior,
        tax_calculation_mode = v_tax_calculation_mode,
        venue_address = nullif(btrim(p_event->>'venue_address'), ''),
        venue_city = nullif(btrim(p_event->>'venue_city'), ''),
        venue_country_code = upper(nullif(btrim(p_event->>'venue_country_code'), '')),
        venue_country_name = nullif(btrim(p_event->>'venue_country_name'), ''),
        venue_name = nullif(btrim(p_event->>'venue_name'), ''),
        venue_state_code = case
            -- Apply an explicitly submitted subdivision code
            when p_event ? 'venue_state_code'
                then upper(nullif(btrim(p_event->>'venue_state_code'), ''))
            -- Clear a code invalidated by a legacy country or subdivision edit
            when upper(nullif(btrim(p_event->>'venue_country_code'), ''))
                    is distinct from upper(nullif(btrim(v_event_before->>'venue_country_code'), ''))
                or (
                    (p_event ? 'venue_state_name' or p_event ? 'venue_state')
                    and nullif(
                        btrim(coalesce(p_event->>'venue_state_name', p_event->>'venue_state')),
                        ''
                    ) is distinct from nullif(btrim(v_event_before->>'venue_state_name'), '')
                ) then null
            -- Preserve the code while the deferred frontend omits this field
            else event.venue_state_code
        end,
        venue_state_name = nullif(
            btrim(coalesce(p_event->>'venue_state_name', p_event->>'venue_state')),
            ''
        ),
        venue_zip_code = nullif(btrim(p_event->>'venue_zip_code'), ''),
        waitlist_enabled = v_event_waitlist_enabled
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false
    and canceled = false;

    -- Synchronize normalized ticketing data after updating the event row
    perform sync_event_discount_codes(p_event_id, v_discount_codes);
    perform sync_event_ticket_types(p_event_id, v_ticket_types);

    -- Validate the settled payment shape without blocking unrelated edits
    perform validate_event_ticketing_payload(
        p_configured_provider,
        v_discount_codes,
        v_payment_currency_code,
        v_payment_recipient,
        v_ticket_types,
        v_ticketing_configuration_changed,
        p_event_id,
        p_event || jsonb_build_object(
            'external_mode', v_external_mode,
            'external_payment_url', v_external_payment_url,
            'external_payment_window_hours', v_external_payment_window_hours,
            'group_country_code', v_group_country_code,
            'manual_tax_rate_ids', to_jsonb(v_manual_tax_rate_ids),
            'tax_calculation_mode', v_tax_calculation_mode
        )
    );

    -- Fill ticket-tier capacity made available by the synchronized payload
    perform reconcile_event_enrollment(
        p_event_id,
        null,
        p_configured_provider
    );

    -- Synchronize event CFS labels
    perform sync_event_cfs_labels(p_event_id, p_event->'cfs_labels');

    -- Synchronize event hosts, speakers, and sponsors
    perform sync_event_hosts_speakers_sponsors(p_event_id, p_event);

    -- Synchronize event sessions and speakers. This must run after the event
    -- row update so the session bounds trigger re-validates retained sessions
    -- against the new event dates
    perform sync_event_sessions(p_event_id, p_event, v_event_before);

    -- Track the updated event
    perform insert_audit_log(
        'event_updated',
        p_actor_user_id,
        'event',
        p_event_id,
        v_community_id,
        p_group_id,
        p_event_id
    );

    -- Return whether the event entered the notifiable paid state
    return not v_is_test_event
        and v_is_paid_capable
        and (v_was_test_event or not v_was_paid_capable);
end;
$$ language plpgsql;
