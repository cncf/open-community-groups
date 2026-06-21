-- update_user_external_profile refreshes fields sourced from external identity providers.
create or replace function update_user_external_profile(
    p_user_id uuid,
    p_user jsonb
) returns void as $$
    update "user"
    set
        name = coalesce(nullif(p_user->>'name', ''), name),
        photo_url = coalesce(nullif(p_user->>'photo_url', ''), photo_url),
        provider = coalesce(provider, '{}'::jsonb) || coalesce(p_user->'provider', '{}'::jsonb)
    where user_id = p_user_id;
$$ language sql;
