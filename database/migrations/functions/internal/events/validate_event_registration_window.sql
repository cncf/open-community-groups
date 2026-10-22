-- Validates that a registration window opens before it closes and that
-- neither configured bound falls after the event start.
create or replace function validate_event_registration_window(
    p_registration_starts_at timestamptz,
    p_registration_ends_at timestamptz,
    p_event_starts_at timestamptz
)
returns void as $$
begin
    -- Require configured registration openings to leave time before close
    if p_registration_starts_at is not null
       and p_registration_ends_at is not null
       and p_registration_starts_at >= p_registration_ends_at then
        raise exception 'registration starts_at must be before registration ends_at' using errcode = 'OCG01';
    end if;

    -- Keep configured registration openings from extending past the event start
    if p_registration_starts_at is not null
       and p_event_starts_at is not null
       and p_registration_starts_at > p_event_starts_at then
        raise exception 'registration starts_at cannot be after event starts_at' using errcode = 'OCG01';
    end if;

    -- Keep configured registration closes from extending past the event start
    if p_registration_ends_at is not null
       and p_event_starts_at is not null
       and p_registration_ends_at > p_event_starts_at then
        raise exception 'registration ends_at cannot be after event starts_at' using errcode = 'OCG01';
    end if;
end;
$$ language plpgsql;
