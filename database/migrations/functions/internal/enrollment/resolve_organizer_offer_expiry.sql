-- Resolves the claim deadline of an organizer-issued admission offer
-- (invitation or approval): 24 hours, bounded by the event start or, once the
-- event is in progress, by its end. Rejects events with no claim window left.
create or replace function resolve_organizer_offer_expiry(p_event event)
returns timestamptz as $$
declare
    v_offer_expires_at timestamptz;
begin
    -- Bound the invitation expiry to the remaining event window
    if p_event.starts_at is not null and p_event.starts_at > current_timestamp then
        v_offer_expires_at := least(current_timestamp + interval '24 hours', p_event.starts_at);

    -- Bound in-progress events by end time instead of start time
    else
        v_offer_expires_at := least(
            current_timestamp + interval '24 hours',
            coalesce(p_event.ends_at, 'infinity'::timestamptz)
        );
    end if;

    -- Reject offers that cannot reserve any remaining claim window
    if v_offer_expires_at <= current_timestamp then
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;

    return v_offer_expires_at;
end;
$$ language plpgsql;
