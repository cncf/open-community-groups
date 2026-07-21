-- Updates a partner integration owned by an alliance.
create or replace function update_partner_integration(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_partner_integration_id uuid,
    p_partner_integration jsonb
)
returns void as $$
begin
    update partner_integration
    set
        name = trim(p_partner_integration->>'name'),
        logo_url = nullif(trim(p_partner_integration->>'logo_url'), ''),
        website_url = nullif(trim(p_partner_integration->>'website_url'), ''),
        attribution_copy = trim(coalesce(p_partner_integration->>'attribution_copy', '')),
        public = coalesce((p_partner_integration->>'public')::boolean, false),
        updated_at = now()
    where alliance_id = p_alliance_id
      and partner_integration_id = p_partner_integration_id;

    if not found then
        raise exception 'partner integration not found';
    end if;

    perform insert_audit_log(
        'partner_integration_updated', p_actor_user_id, 'partner_integration',
        p_partner_integration_id, p_alliance_id
    );
exception
    when unique_violation then raise exception 'partner integration already exists';
end;
$$ language plpgsql;
