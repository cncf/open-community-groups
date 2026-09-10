-- Enforces admission offer immutability and status transitions on update.
create or replace function check_admission_offer_lifecycle()
returns trigger as $$
begin
    -- Keep offer ownership identity immutable
    if row(
        new.created_at,
        new.event_id,
        new.event_ticket_type_id,
        new.organizer_user_id,
        new.source,
        new.user_id
    ) is distinct from row(
        old.created_at,
        old.event_id,
        old.event_ticket_type_id,
        old.organizer_user_id,
        old.source,
        old.user_id
    ) then
        raise exception 'admission offer ownership and deadline fields are immutable';
    end if;

    -- Preserve the stored deadline except when moving into a longer hold
    if new.expires_at is distinct from old.expires_at
       and not (
            admission_offer_is_active(old.status)
            and new.status = 'checkout_pending'
            and new.expires_at >= old.expires_at
       ) then
        raise exception 'admission offer ownership and deadline fields are immutable';
    end if;

    -- Preserve a stored price snapshot except when a pending offer is claimed
    if old.amount_minor is not null
       and not (
            old.status = 'pending'
            and new.status = 'checkout_pending'
       )
       and row(
            new.amount_minor,
            new.currency_code,
            new.discount_amount_minor,
            new.discount_code,
            new.event_discount_code_id,
            new.ticket_title
       ) is distinct from row(
            old.amount_minor,
            old.currency_code,
            old.discount_amount_minor,
            old.discount_code,
            old.event_discount_code_id,
            old.ticket_title
       ) then
        raise exception 'admission offer price snapshot is immutable';
    end if;

    -- Enforce the offer lifecycle while permitting idempotent same-state updates
    if new.status <> old.status
       and not (
            (old.status = 'pending' and new.status in (
                'canceled',
                'checkout_pending',
                'completed',
                'declined',
                'expired'
            ))
            or (
                old.status = 'checkout_pending'
                and new.status in (
                    'canceled',
                    'completed',
                    'declined',
                    'expired',
                    'pending'
                )
            )
       ) then
        raise exception 'invalid admission offer status transition: % -> %', old.status, new.status;
    end if;

    -- Return the validated offer row
    return new;
end;
$$ language plpgsql;
