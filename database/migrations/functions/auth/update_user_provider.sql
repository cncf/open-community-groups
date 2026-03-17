-- update_user_provider refreshes externally sourced provider metadata for a user.
create or replace function update_user_provider(
    p_user_id uuid,
    p_provider jsonb
) returns void as $$
    update "user"
    -- Shallow-merge top-level provider keys; nested provider objects are replaced.
    set provider = coalesce(provider, '{}'::jsonb) || p_provider
    where user_id = p_user_id;
$$ language sql;
