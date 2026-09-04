-- Reconciles the enrollment state of an event under the global lock order:
-- expires stale checkout holds and due admission offers, reminds external
-- payment holders, returns abandoned checkout offers to pending and, while
-- the event accepts public registration, promotes waitlist entries into
-- admission offers. Returns the promoted user identifiers. A scoped ticket
-- type limits the queues that are promoted.
create or replace function reconcile_event_enrollment(
    p_event_id uuid,
    p_event_ticket_type_id uuid default null,
    p_configured_provider text default null
)
returns uuid[] as $$
declare
    v_event event;
    v_group "group";
    v_theme jsonb;
begin
    -- Lock the event before every tier and enrollment row touched below
    select e.*
    into v_event
    from event e
    where e.event_id = p_event_id
    for update of e;

    -- Nothing to reconcile for an unknown event
    if not found then
        return array[]::uuid[];
    end if;

    -- Load the group whose state and payment recipient gate promotions
    select g.*
    into v_group
    from "group" g
    where g.group_id = v_event.group_id;

    -- Take the tier, user, offer and purchase locks in the global order
    perform lock_event_enrollment_rows(p_event_id, p_event_ticket_type_id, null);

    -- Load the site theme once for enrollment notifications
    select s.theme
    into v_theme
    from site s
    limit 1;

    -- Settle expired holds, reminders and due offers before allocating capacity
    perform expire_event_checkout_holds(v_event, v_group, v_theme);
    perform remind_event_external_payment_holds(v_event, v_group, v_theme);
    perform reconcile_event_admission_offers(v_event, v_group);

    -- Stop ticket offer creation when the event is not open or public registration is closed
    if not (
        v_group.active
        and not v_event.canceled
        and not v_event.deleted
        and v_event.published
        and (v_event.starts_at is null or v_event.starts_at > current_timestamp)
    )
    or not is_registration_window_open(
        v_event.registration_starts_at,
        v_event.registration_ends_at,
        v_event.starts_at
    ) then
        return array[]::uuid[];
    end if;

    -- Fill public tier capacity from the waitlists
    return promote_event_waitlist_entries(
        v_event,
        v_group,
        p_event_ticket_type_id,
        p_configured_provider,
        v_theme
    );
end;
$$ language plpgsql;
