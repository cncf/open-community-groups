-- Rotates a credential whenever canceled or incomplete attendance is confirmed.
create or replace function rotate_event_attendee_check_in_code()
returns trigger as $$
begin
    -- Revoke the previous credential on a fresh confirmation
    if new.status = 'confirmed' and old.status <> 'confirmed' then
        new.check_in_code := gen_random_uuid();
    end if;

    -- Continue the attendee update with the current credential
    return new;
end;
$$ language plpgsql;
