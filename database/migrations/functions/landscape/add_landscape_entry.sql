create or replace function add_landscape_entry(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_input jsonb,
    p_tags text[]
) returns uuid language plpgsql as $$
declare
    v_entry_id uuid;
    v_slug_base text;
    v_slug text;
begin
    v_slug_base := regexp_replace(lower(trim(p_input->>'name')), '[^a-z0-9]+', '-', 'g');
    v_slug_base := trim(both '-' from v_slug_base);
    if v_slug_base = '' then
        v_slug_base := 'landscape';
    end if;
    v_slug := left(v_slug_base, 60) || '-' || generate_slug(6);

    insert into landscape_entry (
        alliance_id,
        added_by_user_id,
        name,
        slug,
        kind,
        summary,
        description,
        website_url,
        github_url,
        logo_url,
        category,
        tags
    )
    values (
        p_alliance_id,
        p_actor_user_id,
        trim(p_input->>'name'),
        v_slug,
        trim(p_input->>'kind'),
        trim(p_input->>'summary'),
        nullif(trim(p_input->>'description'), ''),
        nullif(trim(p_input->>'website_url'), ''),
        nullif(trim(p_input->>'github_url'), ''),
        nullif(trim(p_input->>'logo_url'), ''),
        nullif(trim(p_input->>'category'), ''),
        coalesce(p_tags, '{}'::text[])
    )
    returning landscape_entry_id into v_entry_id;

    perform insert_audit_log(
        'landscape_entry_added',
        p_actor_user_id,
        'landscape_entry',
        v_entry_id,
        p_alliance_id,
        null
    );

    return v_entry_id;
end;
$$;
