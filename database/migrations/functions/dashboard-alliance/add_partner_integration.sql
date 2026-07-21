-- Adds a partner integration to an alliance.
create or replace function add_partner_integration(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_partner_integration jsonb
)
returns uuid as $$
declare
    v_partner_integration_id uuid;
begin
    insert into partner_integration (
        alliance_id, name, logo_url, website_url, attribution_copy, public
    ) values (
        p_alliance_id,
        trim(p_partner_integration->>'name'),
        nullif(trim(p_partner_integration->>'logo_url'), ''),
        nullif(trim(p_partner_integration->>'website_url'), ''),
        trim(coalesce(p_partner_integration->>'attribution_copy', '')),
        coalesce((p_partner_integration->>'public')::boolean, false)
    )
    returning partner_integration_id into v_partner_integration_id;

    perform insert_audit_log(
        'partner_integration_added', p_actor_user_id, 'partner_integration',
        v_partner_integration_id, p_alliance_id
    );
    return v_partner_integration_id;
exception
    when unique_violation then raise exception 'partner integration already exists';
end;
$$ language plpgsql;
