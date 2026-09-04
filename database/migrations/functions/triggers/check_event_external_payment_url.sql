-- Prevents clearing an event's external payment URL while external holds are pending.
create or replace function check_event_external_payment_url()
returns trigger as $$
begin
    -- Allow assignment, replacement, and no-op URL updates
    if new.external_payment_url is not null
       or old.external_payment_url is null then
        return new;
    end if;

    -- Reject clearing the URL while an external hold can still be resumed
    if exists (
        select 1
        from event_purchase ep
        where ep.event_id = old.event_id
        and ep.charge_model = 'external'
        and ep.status = 'pending'
    ) then
        raise exception 'external payment url cannot be cleared while pending external purchases exist' using errcode = 'OCG01';
    end if;

    -- Return the validated event row
    return new;
end;
$$ language plpgsql;
