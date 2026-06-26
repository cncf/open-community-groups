create or replace function add_job(p_user_id uuid, p_input jsonb, p_tags text[])
returns uuid language plpgsql as $$
declare
    v_job_id uuid;
    v_slug_base text;
    v_slug text;
begin
    v_slug_base := regexp_replace(lower(trim(p_input->>'title')), '[^a-z0-9]+', '-', 'g');
    v_slug_base := trim(both '-' from v_slug_base);
    if v_slug_base = '' then
        v_slug_base := 'job';
    end if;
    v_slug := left(v_slug_base, 60) || '-' || generate_slug(6);

    insert into jobs_job (
        posted_by_user_id,
        title,
        slug,
        company_name,
        summary,
        description,
        apply_url,
        location,
        remote,
        members_only,
        tags
    )
    values (
        p_user_id,
        trim(p_input->>'title'),
        v_slug,
        trim(p_input->>'company_name'),
        trim(p_input->>'summary'),
        trim(p_input->>'description'),
        trim(p_input->>'apply_url'),
        nullif(trim(p_input->>'location'), ''),
        coalesce((p_input->>'remote')::boolean, false),
        coalesce((p_input->>'members_only')::boolean, false),
        coalesce(p_tags, '{}'::text[])
    )
    returning job_id into v_job_id;

    return v_job_id;
end;
$$;
