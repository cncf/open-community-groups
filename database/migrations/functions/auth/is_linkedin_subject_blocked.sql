create or replace function is_linkedin_subject_blocked(p_linkedin_subject text)
returns boolean as $$
    select exists (
        select 1
        from linkedin_blocklist
        where linkedin_subject = p_linkedin_subject
    );
$$ language sql stable;
