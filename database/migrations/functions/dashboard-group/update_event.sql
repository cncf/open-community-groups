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
    v_before event;
    v_community_id uuid;
    v_event event;
    v_group_country_code text;
    v_group_external_ready boolean;
    v_is_paid_capable boolean;
    v_payload record;
    v_payment_recipient jsonb;
    v_ticketing_configuration_changed boolean;
    v_was_paid_capable boolean;
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
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;

    -- Lock the event row whose prior state drives the update
    select e.*
    into v_before
    from event e
    where e.group_id = p_group_id
    and e.event_id = p_event_id
    and e.deleted = false
    and e.canceled = false
    for update of e;

    -- Reject missing or inactive events before resolving the update
    if not found then
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;

    -- Resolve the event columns, ticket configuration and payment rail from the payload
    select *
    into v_payload
    from resolve_event_payload(p_event, v_before, v_group_external_ready);
    v_event := v_payload.resolved;
    v_is_paid_capable := is_event_ticketing_payload_paid_capable(v_payload.ticket_types);
    v_was_paid_capable := is_event_paid_capable(p_event_id);

    -- Detect paid-readiness changes against the stored configuration
    v_ticketing_configuration_changed := event_ticketing_configuration_changed(
        v_community_id,
        p_group_id,
        p_event_id,
        p_event || jsonb_build_object(
            'external_payment_instructions', v_event.external_payment_instructions,
            'external_payment_url', v_event.external_payment_url,
            'external_payment_window_hours', v_event.external_payment_window_hours
        )
    );

    -- Bind provider validation to the recipient protected by the group lock
    if p_configured_provider is not null
       and v_is_paid_capable
       and v_ticketing_configuration_changed
       and not v_payload.external_mode then
        perform validate_event_payment_validation(
            p_event,
            v_payment_recipient,
            v_event.manual_tax_rate_ids,
            v_event.tax_behavior,
            v_event.tax_calculation_mode
        );
    end if;

    -- Validate registration questions and prevent changing definitions with live user state
    perform validate_questionnaire_questions_payload(v_event.registration_questions);

    -- Protect submitted questionnaire answers and active checkout holds
    if v_event.registration_questions <> coalesce(v_before.registration_questions, '[]'::jsonb) then
        -- Reject changes after attendees submit answers
        if questionnaire_answers_exist_for_event(p_event_id) then
            raise exception 'registration questions cannot be changed after attendees have submitted answers' using errcode = 'OCG01';
        end if;

        -- Reject changes while pending purchases hold questionnaire state
        if exists (
            select 1
            from event_purchase ep
            where ep.event_id = p_event_id
            and ep.status = 'pending'
            and ep.hold_expires_at > current_timestamp
        ) then
            raise exception 'registration questions cannot be changed while checkout holds are active' using errcode = 'OCG01';
        end if;
    end if;

    -- Clear stale currency when the last positive price is removed without discounts
    if not v_is_paid_capable and v_payload.discount_codes is null then
        v_event.payment_currency_code := null;
    end if;

    -- Keep approval enabled while invitation requests await a decision
    if not v_event.attendee_approval_required and exists (
        select 1
        from event_invitation_request eir
        where eir.event_id = p_event_id
        and eir.status = 'pending'
    ) then
        raise exception 'approval-required events with pending invitation requests cannot disable approval' using errcode = 'OCG01';
    end if;

    -- Block approval-required attendance while queued users exist
    if v_event.attendee_approval_required and exists (
        select 1
        from event_waitlist ew
        where ew.event_id = p_event_id
    ) then
        raise exception 'approval-required events cannot have existing waitlist entries' using errcode = 'OCG01';
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
        false,
        p_event_id,
        p_event || jsonb_build_object(
            'external_mode', v_payload.external_mode,
            'external_payment_url', v_event.external_payment_url,
            'external_payment_window_hours', v_event.external_payment_window_hours,
            'group_country_code', v_group_country_code,
            'manual_tax_rate_ids', to_jsonb(v_event.manual_tax_rate_ids),
            'tax_calculation_mode', v_event.tax_calculation_mode
        )
    );

    -- Validate update-specific event and session date rules
    perform validate_update_event_dates(p_event, v_before);

    -- Validate capacity
    perform validate_event_capacity(
        p_event,
        p_cfg_max_participants,
        p_existing_event_id => p_event_id,
        p_effective_capacity => v_event.capacity
    );

    -- Validate CFS labels rules
    perform validate_event_cfs_labels_payload(p_event->'cfs_labels');

    -- Update event
    update event set
        name = v_event.name,
        description = v_event.description,
        test_event = v_event.test_event,
        timezone = v_event.timezone,
        event_category_id = v_event.event_category_id,
        event_kind_id = v_event.event_kind_id,

        attendee_approval_required = v_event.attendee_approval_required,
        banner_mobile_url = v_event.banner_mobile_url,
        banner_url = v_event.banner_url,
        cfs_description = v_event.cfs_description,
        cfs_enabled = v_event.cfs_enabled,
        cfs_ends_at = v_event.cfs_ends_at,
        cfs_starts_at = v_event.cfs_starts_at,
        description_short = v_event.description_short,
        ends_at = v_event.ends_at,
        event_reminder_enabled = v_event.event_reminder_enabled,
        -- Mark reminder as evaluated when update moves start time inside the 24-hour window
        event_reminder_evaluated_for_starts_at = case
            -- Record the newly eligible reminder schedule
            when v_event.event_reminder_enabled = true
                 and event_reminder_sent_at is null
                 and starts_at is distinct from v_event.starts_at
                 and (
                     starts_at is null
                     or starts_at <= current_timestamp
                     or starts_at > current_timestamp + interval '24 hours'
                 )
                 and v_event.starts_at is not null
                 and v_event.starts_at > current_timestamp
                 and v_event.starts_at <= current_timestamp + interval '24 hours'
            then v_event.starts_at
            -- Preserve the prior reminder evaluation schedule
            else event_reminder_evaluated_for_starts_at
        end,
        external_payment_instructions = v_event.external_payment_instructions,
        external_payment_url = v_event.external_payment_url,
        external_payment_window_hours = v_event.external_payment_window_hours,
        location = v_event.location,
        logo_url = v_event.logo_url,
        luma_url = v_event.luma_url,
        manual_tax_rate_ids = v_event.manual_tax_rate_ids,
        meeting_hosts = v_event.meeting_hosts,
        meeting_in_sync = case
            -- Preserve pending meeting deletion work
            when v_before.meeting_in_sync = false
                 and v_event.meeting_requested is distinct from false
            then false
            -- Recompute meeting synchronization for other updates
            else is_event_meeting_in_sync(v_before, p_event)
        end,
        meeting_join_instructions = v_event.meeting_join_instructions,
        meeting_join_url = v_event.meeting_join_url,
        meeting_provider_id = v_event.meeting_provider_id,
        meeting_recording_published = v_event.meeting_recording_published,
        meeting_recording_requested = v_event.meeting_recording_requested,
        meeting_recording_url = v_event.meeting_recording_url,
        meeting_requested = v_event.meeting_requested,
        meetup_url = v_event.meetup_url,
        payment_currency_code = v_event.payment_currency_code,
        photos_urls = v_event.photos_urls,
        registration_ends_at = v_event.registration_ends_at,
        registration_questions = v_event.registration_questions,
        registration_starts_at = v_event.registration_starts_at,
        starts_at = v_event.starts_at,
        tags = v_event.tags,
        tax_behavior = v_event.tax_behavior,
        tax_calculation_mode = v_event.tax_calculation_mode,
        venue_address = v_event.venue_address,
        venue_city = v_event.venue_city,
        venue_country_code = v_event.venue_country_code,
        venue_country_name = v_event.venue_country_name,
        venue_name = v_event.venue_name,
        venue_state_code = v_event.venue_state_code,
        venue_state_name = v_event.venue_state_name,
        venue_zip_code = v_event.venue_zip_code,
        waitlist_enabled = v_event.waitlist_enabled
    where event_id = p_event_id;

    -- Synchronize normalized ticketing data after updating the event row
    perform sync_event_discount_codes(p_event_id, v_payload.discount_codes);
    perform sync_event_ticket_types(p_event_id, v_payload.ticket_types);

    -- Validate the settled payment shape without blocking unrelated edits
    perform validate_event_ticketing_payload(
        p_configured_provider,
        v_payload.discount_codes,
        v_event.payment_currency_code,
        v_payment_recipient,
        v_payload.ticket_types,
        v_ticketing_configuration_changed,
        p_event_id,
        p_event || jsonb_build_object(
            'external_mode', v_payload.external_mode,
            'external_payment_url', v_event.external_payment_url,
            'external_payment_window_hours', v_event.external_payment_window_hours,
            'group_country_code', v_group_country_code,
            'manual_tax_rate_ids', to_jsonb(v_event.manual_tax_rate_ids),
            'tax_calculation_mode', v_event.tax_calculation_mode
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

    -- Synchronize event sessions and speakers. This must run after the event
    -- row update so the session bounds trigger re-validates retained sessions
    -- against the new event dates, and before the event hosts are replaced so
    -- session meeting sync still compares against the prior host rows
    perform sync_event_sessions(p_event_id, p_event, v_before);

    -- Synchronize event hosts, speakers, and sponsors
    perform sync_event_hosts_speakers_sponsors(p_event_id, p_event);

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
    return not v_event.test_event
        and v_is_paid_capable
        and (v_before.test_event or not v_was_paid_capable);
end;
$$ language plpgsql;
