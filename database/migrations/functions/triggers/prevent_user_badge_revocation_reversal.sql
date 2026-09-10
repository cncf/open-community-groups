-- Protects immutable issuance fields and prevents revoked badges from returning active.
create or replace function prevent_user_badge_revocation_reversal()
returns trigger as $$
begin
    -- Preserve the credential inputs captured at issuance
    if new.awarded_at is distinct from old.awarded_at
        or new.badge_status_list_id is distinct from old.badge_status_list_id
        or new.group_id is distinct from old.group_id
        or new.snapshot is distinct from old.snapshot
        or new.status_list_index is distinct from old.status_list_index
        or new.user_badge_id is distinct from old.user_badge_id
        or (
            new.badge_id is distinct from old.badge_id
            and not (old.badge_id is not null and new.badge_id is null)
        )
        or (
            new.event_id is distinct from old.event_id
            and not (old.event_id is not null and new.event_id is null)
        )
        or (
            new.user_id is distinct from old.user_id
            and not (old.user_id is not null and new.user_id is null)
        )
    then
        raise exception 'badge issuance fields cannot be changed';
    end if;

    -- Keep every revoked credential hidden from its holder profile
    if new.revoked_at is not null and new.is_listed then
        raise exception 'revoked badge cannot be listed';
    end if;

    -- Preserve the original private reason and actor after revocation
    if old.revoked_at is not null
        and (
            new.revocation_reason is distinct from old.revocation_reason
            or (
                new.revoked_by_user_id is distinct from old.revoked_by_user_id
                and not (
                    old.revoked_by_user_id is not null
                    and new.revoked_by_user_id is null
                )
            )
        )
    then
        raise exception 'badge revocation metadata cannot be changed';
    end if;

    -- Preserve the first durable revocation timestamp
    if old.revoked_at is not null
        and new.revoked_at is distinct from old.revoked_at
    then
        raise exception 'badge revocation cannot be changed';
    end if;

    -- Return the validated credential row
    return new;
end;
$$ language plpgsql;
