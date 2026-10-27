-- publish_event sets published=true and records publication metadata for an event.
create or replace function publish_event(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_configured_provider text,
    p_payment_validation jsonb default null
)
returns void as $$
declare
    v_event event;
    v_external_mode boolean := false;
    v_group "group";
    v_group_external_ready boolean;
    v_group_external_selected boolean;
    v_paid_capable boolean;
begin
    -- Lock the group payment state before the event so recipient changes and
    -- paid ticket or publication updates cannot invalidate each other
    v_group := lock_active_group(null, p_group_id);
    v_group_external_ready := is_group_external_payments_ready(p_group_id);
    v_group_external_selected := is_group_external_payments_selected(p_group_id);

    -- Lock the event, if not deleted or canceled, and read its paid capability
    v_event := lock_manageable_event(p_group_id, p_event_id, false);
    v_paid_capable := is_event_paid_capable(p_event_id);

    -- Return early when the event is already published
    if v_event.published then
        return;
    end if;

    -- Reject publication while co-host invitations are unanswered
    if event_has_pending_cohosts(p_event_id) then
        raise exception 'co-hosts must respond before the event can be published' using errcode = 'OCG01';
    end if;

    -- Reject publishing an external-marked event while the group has not selected the rail
    if v_event.external_payment_url is not null and not v_group_external_selected then
        raise exception 'external payments are not available for this event' using errcode = 'OCG01';
    end if;

    -- Use the external rail only while the group selects it right now
    v_external_mode := v_paid_capable and v_group_external_selected;

    -- Reject paid external publication while the group cannot collect on its rail
    if v_external_mode and not v_group_external_ready then
        raise exception 'external payments require the legal name of the organization collecting payments' using errcode = 'OCG01';
    end if;

    -- Clear leftover windows only when the event is not on the external rail
    if not v_external_mode then
        v_event.external_payment_window_hours := null;
    end if;

    -- Bind provider validation to the recipient protected by the group lock
    if p_configured_provider is not null
       and v_paid_capable
       and not v_external_mode
       and (
           not payment_validation_snapshot_matches(
               p_payment_validation,
               v_group.payment_recipient,
               v_group.payment_recipient
           )
           or (
               v_event.tax_calculation_mode = 'automatic'
               and not (p_payment_validation->>'require_automatic_tax')::boolean
           )
       ) then
        raise exception 'payment configuration changed during provider validation' using errcode = 'OCG01';
    end if;

    -- Require checkout-critical payment configuration only for paid-capable events
    perform validate_event_ticketing_payment_readiness(
        p_configured_provider,
        v_paid_capable,
        v_event.payment_currency_code,
        v_group.payment_recipient,
        v_event,
        v_external_mode,
        v_group.country_code
    );

    -- Check that the event has a start date
    if v_event.starts_at is null then
        raise exception 'event must have a start date to be published' using errcode = 'OCG01';
    end if;

    -- Update event to mark as published
    update event set
        external_payment_instructions = case
            -- Keep external payment details on the external rail
            when v_external_mode then external_payment_instructions
            -- Clear external payment details on the provider rail
            else null
        end,
        external_payment_url = case
            -- Keep external payment details on the external rail
            when v_external_mode then external_payment_url
            -- Clear external payment details on the provider rail
            else null
        end,
        external_payment_window_hours = case
            -- Keep external payment details on the external rail
            when v_external_mode then external_payment_window_hours
            -- Clear external payment details on the provider rail
            else null
        end,
        published = true,
        published_at = now(),
        published_by = p_actor_user_id,
        -- Mark reminder as evaluated when publish happens inside the 24-hour window
        event_reminder_evaluated_for_starts_at = case
            -- Record the reminder schedule when publish happens inside the 24-hour window
            when event_reminder_enabled = true
                 and event_reminder_sent_at is null
                 and starts_at > current_timestamp
                 and starts_at <= current_timestamp + interval '24 hours'
            then starts_at
            -- Preserve the prior reminder evaluation schedule
            else event_reminder_evaluated_for_starts_at
        end
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false
    and canceled = false;

    -- Request provider setup of the event and session meetings
    perform mark_event_meetings_out_of_sync(p_event_id);

    -- Track the publish action
    perform insert_audit_log(
        'event_published',
        p_actor_user_id,
        'event',
        p_event_id,
        v_group.community_id,
        p_group_id,
        p_event_id
    );
end;
$$ language plpgsql;
