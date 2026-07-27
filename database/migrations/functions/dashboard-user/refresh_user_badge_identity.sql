-- Ensures an active owned badge carries an identity binding for the owner's current email.
create or replace function refresh_user_badge_identity(
    p_user_id uuid,
    p_user_badge_id uuid
)
returns json as $$
declare
    v_binding json;
    v_salt text := replace(gen_random_uuid()::text, '-', '');
begin
    -- Rebind atomically only when the stored identity is missing or stale
    update user_badge ub
    set
        identity_bound_at = current_timestamp,
        identity_hash = encode(digest(lower(u.email) || v_salt, 'sha256'), 'hex'),
        identity_salt = v_salt
    from "user" u
    where u.user_id = ub.user_id
    and ub.user_badge_id = p_user_badge_id
    and ub.user_id = p_user_id
    and ub.revoked_at is null
    and (
        ub.identity_hash is null
        or ub.identity_hash <> encode(digest(lower(u.email) || ub.identity_salt, 'sha256'), 'hex')
    );

    -- Return the current binding for the active owned award
    select json_build_object(
        'identity_bound_at', ub.identity_bound_at,
        'identity_hash', ub.identity_hash,
        'identity_salt', ub.identity_salt
    )
    into v_binding
    from user_badge ub
    where ub.user_badge_id = p_user_badge_id
    and ub.user_id = p_user_id
    and ub.revoked_at is null
    and ub.identity_bound_at is not null;

    if not found then
        raise exception 'active user badge not found';
    end if;

    return v_binding;
end;
$$ language plpgsql;
