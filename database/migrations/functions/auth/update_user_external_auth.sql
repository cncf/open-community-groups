-- Updates verified external-auth identity details for a registered user.
create or replace function update_user_external_auth(
    p_user_id uuid,
    p_user jsonb
)
returns json as $$
declare
    v_email text := lower(nullif(btrim(p_user->>'email'), ''));
    v_lf_issuer text := nullif(p_user #>> '{provider,linuxfoundation,issuer}', '');
    v_lf_subject text := nullif(p_user #>> '{provider,linuxfoundation,subject}', '');
    v_name text := nullif(btrim(p_user->>'name'), '');
    v_provider jsonb := p_user->'provider';
begin
    -- Validate required external-auth email
    if v_email is null then
        raise exception 'external auth email is required';
    end if;

    -- Reject email addresses owned by another user
    if exists (
        select 1
        from "user" u
        where lower(u.email) = v_email
        and u.user_id <> p_user_id
    ) then
        raise exception 'external auth email belongs to another user';
    end if;

    -- Reject LF OIDC identities owned by another user
    if v_lf_issuer is not null and v_lf_subject is not null and exists (
        select 1
        from "user" u
        where u.provider #>> '{linuxfoundation,issuer}' = v_lf_issuer
        and u.provider #>> '{linuxfoundation,subject}' = v_lf_subject
        and u.user_id <> p_user_id
    ) then
        raise exception 'external auth identity belongs to another user';
    end if;

    -- Sync verified external-auth identity details
    update "user"
    set
        email = v_email,
        email_verified = true,
        name = coalesce(v_name, name),
        provider = case
            when p_user ? 'provider' and jsonb_typeof(v_provider) = 'object'
                then coalesce(provider, '{}'::jsonb) || v_provider
            else provider
        end
    where user_id = p_user_id
    and registration_status = 'registered';

    -- Ensure a registered user was updated
    if not found then
        raise exception 'registered external-auth user not found';
    end if;

    -- Return an external-auth payload with required defaults
    return (
        select (
            get_user_by_id(u.user_id, false)::jsonb
            || jsonb_build_object('name', coalesce(u.name, ''))
        )::json
        from "user" u
        where u.user_id = p_user_id
    );
end;
$$ language plpgsql;
