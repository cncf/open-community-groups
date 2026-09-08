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
    v_community_id uuid;
    v_external_mode boolean := false;
    v_external_payment_url text;
    v_external_payment_window_hours int;
    v_group_country_code text;
    v_group_external_ready boolean := false;
    v_paid_capable boolean;
    v_payment_currency_code text;
    v_payment_recipient jsonb;
    v_published boolean;
    v_starts_at timestamptz;
    v_tax_calculation_mode text;
begin
    -- Lock the group payment state before the event so recipient changes and
    -- publication cannot invalidate each other
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

    -- Check if the event is active and lock it for publication
    select
        e.external_payment_url,
        e.external_payment_window_hours,
        e.published,
        e.payment_currency_code,
        e.starts_at,
        e.tax_calculation_mode,
        is_event_paid_capable(e.event_id)
    into
        v_external_payment_url,
        v_external_payment_window_hours,
        v_published,
        v_payment_currency_code,
        v_starts_at,
        v_tax_calculation_mode,
        v_paid_capable
    from event e
    where event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false
    and e.canceled = false
    for update of e;

    -- Reject missing or inactive events before resolving publication
    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Return early when the event is already published
    if v_published then
        return;
    end if;

    -- Reject publishing an external-marked event while the group is ineligible
    if v_external_payment_url is not null and not v_group_external_ready then
        raise exception 'external payments are not available for this event';
    end if;

    -- Use the external rail only while the group is eligible right now
    v_external_mode := v_paid_capable and v_group_external_ready;

    -- Clear leftover windows only when the event is not on the external rail
    if not v_external_mode then
        v_external_payment_window_hours := null;
    end if;

    -- Bind provider validation to the recipient protected by the group lock
    if p_configured_provider is not null
       and v_paid_capable
       and not v_external_mode
       and (
           p_payment_validation is null
           or not (p_payment_validation ? 'expected_payment_recipient')
           or not (p_payment_validation ? 'validated_payment_recipient')
           or not (p_payment_validation ? 'require_automatic_tax')
           or v_payment_recipient is distinct from nullif(
               p_payment_validation->'expected_payment_recipient',
               'null'::jsonb
           )
           or v_payment_recipient is distinct from nullif(
               p_payment_validation->'validated_payment_recipient',
               'null'::jsonb
           )
           or (
               v_tax_calculation_mode = 'automatic'
               and not (p_payment_validation->>'require_automatic_tax')::boolean
           )
       ) then
        raise exception 'payment configuration changed during provider validation';
    end if;

    -- Require checkout-critical payment configuration only for paid-capable events
    perform validate_event_ticketing_payment_readiness(
        p_configured_provider,
        v_paid_capable,
        v_payment_currency_code,
        v_payment_recipient,
        p_event_id,
        null,
        v_external_mode,
        v_external_payment_url,
        v_external_payment_window_hours,
        v_group_country_code
    );

    -- Check that the event has a start date
    if v_starts_at is null then
        raise exception 'event must have a start date to be published';
    end if;

    -- Update event to mark as published
    -- Also set meeting_in_sync to false to trigger meeting setup when applicable
    update event set
        external_payment_instructions = case
            when v_external_mode then external_payment_instructions
            else null
        end,
        external_payment_url = case
            when v_external_mode then external_payment_url
            else null
        end,
        external_payment_window_hours = case
            when v_external_mode then external_payment_window_hours
            else null
        end,
        meeting_in_sync = case
            when meeting_requested = true then false
            else meeting_in_sync
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

    -- Mark sessions as out of sync to trigger meeting creation
    update session set meeting_in_sync = false
    where event_id = p_event_id
    and meeting_requested = true;

    -- Track the publish action
    perform insert_audit_log(
        'event_published',
        p_actor_user_id,
        'event',
        p_event_id,
        v_community_id,
        p_group_id,
        p_event_id
    );
end;
$$ language plpgsql;
