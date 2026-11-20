-- Resolves a unique username by appending a numeric suffix when needed.
create or replace function resolve_unique_username(
    p_base_username text,
    p_excluded_user_id uuid default null
)
returns text as $$
declare
    v_username text := p_base_username;
    v_username_exists boolean;
begin
    -- Check whether the base username is available
    v_username_exists := exists(
        select 1
        from "user"
        where lower(username) = lower(v_username)
        and (
            p_excluded_user_id is null
            or user_id <> p_excluded_user_id
        )
    );

    -- Try numeric suffixes from 2 to 99 when the base username is taken
    if v_username_exists then
        -- Probe each suffixed variant until one is available
        for v_suffix in 2..99 loop
            -- Build the suffixed candidate and check its availability
            v_username := p_base_username || v_suffix;
            v_username_exists := exists(
                select 1
                from "user"
                where lower(username) = lower(v_username)
                and (
                    p_excluded_user_id is null
                    or user_id <> p_excluded_user_id
                )
            );

            -- Stop at the first available variant
            exit when not v_username_exists;
        end loop;

        -- Reject when every suffixed variant is taken
        if v_username_exists then
            raise exception 'unable to generate unique username: all variants from % to %99 are taken',
                p_base_username,
                p_base_username;
        end if;
    end if;

    -- Return the resolved username
    return v_username;
end;
$$ language plpgsql stable;
