-- Returns a verified registered user by Linux Foundation OIDC identity for external authentication.
create or replace function get_user_by_linuxfoundation_identity_for_external_auth(
    p_issuer text,
    p_subject text
)
returns json as $$
declare
    v_issuer text := nullif(p_issuer, '');
    v_subject text := nullif(p_subject, '');
begin
    -- Ignore incomplete identities
    if v_issuer is null or v_subject is null then
        return null;
    end if;

    -- Return an external-auth payload with required defaults
    return (
        select (
            get_user_by_id(u.user_id, false)::jsonb
            || jsonb_build_object(
                'name', coalesce(u.name, ''),
                'registration_status', u.registration_status
            )
        )::json
        from "user" u
        where u.provider #>> '{linuxfoundation,issuer}' = v_issuer
        and u.provider #>> '{linuxfoundation,subject}' = v_subject
        and u.registration_status = 'registered'
        and u.email_verified = true
    );
end;
$$ language plpgsql;
