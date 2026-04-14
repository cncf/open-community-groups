-- publish_event sets published=true and records publication metadata for an event.
create or replace function publish_event(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_configured_provider text
)
returns void as $$
declare
    v_has_ticket_types boolean;
    v_payment_recipient jsonb;
    v_payment_currency_code text;
    v_starts_at timestamptz;
begin
    -- Check if the event is active, load ticketing state, and lock it for update
    select
        exists (
            select 1
            from event_ticket_type ett
            where ett.event_id = e.event_id
        ),
        g.payment_recipient,
        e.payment_currency_code,
        e.starts_at
    into
        v_has_ticket_types,
        v_payment_recipient,
        v_payment_currency_code,
        v_starts_at
    from event e
    join "group" g on g.group_id = e.group_id
    where event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false
    and e.canceled = false
    for update of e;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Require checkout-critical ticketing configuration before publishing
    if v_has_ticket_types then
        if p_configured_provider is null then
            raise exception 'payments are not configured on this server';
        end if;

        if v_payment_recipient is null then
            raise exception 'ticketed events require a payment recipient';
        end if;

        if coalesce(v_payment_recipient->>'provider', '') <> p_configured_provider then
            raise exception 'ticketed events require a payment recipient for the server payments provider';
        end if;

        if v_payment_currency_code is null then
            raise exception 'ticketed events require payment_currency_code';
        end if;
    end if;

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
        (select community_id from "group" where group_id = p_group_id),
        p_group_id,
        p_event_id
    );
end;
$$ language plpgsql;
