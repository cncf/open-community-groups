-- Requires direct purchases to claim an active admission offer instead of bypassing it.
create or replace function check_event_purchase_admission_offer()
returns trigger as $$
begin
    -- Allow existing direct purchases to continue through financial recovery
    if tg_op = 'UPDATE'
       and new.status in ('refund-pending', 'refund-recovery-pending')
       and row(
            new.admission_offer_id,
            new.event_id,
            new.user_id
       ) is not distinct from row(
            old.admission_offer_id,
            old.event_id,
            old.user_id
       ) then
        return new;
    end if;

    -- Ignore historical purchases and purchases explicitly linked to an offer
    if new.admission_offer_id is not null
       or not (
            event_purchase_holds_seat(new.status)
            or new.status = 'pending'
       ) then
        return new;
    end if;

    -- Serialize direct purchase creation with offer allocation
    perform pg_advisory_xact_lock(hashtext(new.event_id::text), hashtext(new.user_id::text));

    -- Reject direct purchases while the user holds an active offer
    if exists (
        select 1
        from admission_offer ao
        where ao.event_id = new.event_id
        and ao.user_id = new.user_id
        and admission_offer_is_active(ao.status)
    ) then
        raise exception 'active admission offer must be claimed directly' using errcode = 'OCG01';
    end if;

    -- Return the validated purchase row
    return new;
end;
$$ language plpgsql;
