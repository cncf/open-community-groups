-- Returns public-safe external provider metadata for user profile payloads.
create or replace function get_public_user_provider(
    p_provider jsonb
)
returns jsonb as $$
    with public_provider as (
        select jsonb_strip_nulls(jsonb_build_object(
            'github', case
                when nullif(btrim(p_provider #>> '{github,username}'), '') is not null
                    then jsonb_build_object(
                        'username', btrim(p_provider #>> '{github,username}')
                    )
            end,
            'linuxfoundation', case
                when nullif(btrim(p_provider #>> '{linuxfoundation,username}'), '') is not null
                    then jsonb_build_object(
                        'username', btrim(p_provider #>> '{linuxfoundation,username}')
                    )
            end
        )) as provider
    )
    select nullif(provider, '{}'::jsonb)
    from public_provider;
$$ language sql;
