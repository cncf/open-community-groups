create or replace function update_job(p_user_id uuid, p_job_id uuid, p_input jsonb, p_tags text[])
returns void language plpgsql as $$
begin
    update jobs_job
    set title = trim(p_input->>'title'),
        company_name = trim(p_input->>'company_name'),
        summary = trim(p_input->>'summary'),
        description = trim(p_input->>'description'),
        apply_url = trim(p_input->>'apply_url'),
        location = nullif(trim(p_input->>'location'), ''),
        remote = coalesce((p_input->>'remote')::boolean, false),
        members_only = coalesce((p_input->>'members_only')::boolean, false),
        tags = coalesce(p_tags, '{}'::text[]),
        updated_at = current_timestamp
    where job_id = p_job_id
    and posted_by_user_id = p_user_id;

    if not found then
        raise exception 'job not found';
    end if;
end;
$$;
