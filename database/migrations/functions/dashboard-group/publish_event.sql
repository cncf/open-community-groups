-- publish_event sets published=true and records publication metadata for an event.
create or replace function publish_event(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_configured_provider text
)
returns void as $$
declare
    v_community_id uuid;
    v_paid_capable boolean;
    v_payment_currency_code text;
    v_payment_recipient jsonb;
    v_published boolean;
    v_starts_at timestamptz;
begin
    -- Lock the group payment state before the event so recipient changes and
    -- publication cannot invalidate each other
    select
        g.community_id,
        g.payment_recipient
    into
        v_community_id,
        v_payment_recipient
    from "group" g
    where g.group_id = p_group_id
    and g.deleted = false
    for update;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Check if the event is active and lock it for publication
    select
        e.published,
        e.payment_currency_code,
        e.starts_at,
        is_event_paid_capable(e.event_id)
    into
        v_published,
        v_payment_currency_code,
        v_starts_at,
        v_paid_capable
    from event e
    where event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false
    and e.canceled = false
    for update of e;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Return early when the event is already published
    if v_published then
        return;
    end if;

    -- Require checkout-critical payment configuration only for paid-capable events
    perform validate_event_ticketing_payment_readiness(
        p_configured_provider,
        v_paid_capable,
        v_payment_currency_code,
        v_payment_recipient
    );

    -- Check that the event has a start date
    if v_starts_at is null then
        raise exception 'event must have a start date to be published';
    end if;

    -- Update event to mark as published
    -- Also set meeting_in_sync to false to trigger meeting setup when applicable
    update event set
        meeting_in_sync = case
            when meeting_requested = true then false
            else meeting_in_sync
        end,
        published = true,
        published_at = now(),
        published_by = p_actor_user_id,
        -- Mark reminder as evaluated when publish happens inside the 24-hour window
        event_reminder_evaluated_for_starts_at = case
            when event_reminder_enabled = true
                 and event_reminder_sent_at is null
                 and starts_at > current_timestamp
                 and starts_at <= current_timestamp + interval '24 hours'
            then starts_at
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
