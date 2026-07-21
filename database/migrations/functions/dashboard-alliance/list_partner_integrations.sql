-- Lists all partner integrations for an alliance dashboard.
create or replace function list_partner_integrations(p_alliance_id uuid)
returns json as $$
    select coalesce(json_agg(
        json_build_object(
            'attribution_copy', pi.attribution_copy,
            'logo_url', pi.logo_url,
            'name', pi.name,
            'partner_integration_id', pi.partner_integration_id,
            'public', pi.public,
            'website_url', pi.website_url
        ) order by pi.name
    ), '[]')
    from partner_integration pi
    where pi.alliance_id = p_alliance_id;
$$ language sql stable;
