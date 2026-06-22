create or replace function job_application_summary_json(p_application jobs_application)
returns jsonb language sql stable as $$
    select jsonb_build_object(
        'job_application_id', p_application.job_application_id,
        'applicant_user_id', p_application.applicant_user_id,
        'applicant_username', u.username,
        'applicant_email', u.email,
        'applicant_name', u.name,
        'applicant_photo_url', u.photo_url,
        'applicant_title', u.title,
        'applicant_company', u.company,
        'applicant_linkedin_url', u.linkedin_url,
        'note', p_application.note,
        'created_at', extract(epoch from p_application.created_at)::bigint
    )
    from "user" u
    where u.user_id = p_application.applicant_user_id;
$$;
