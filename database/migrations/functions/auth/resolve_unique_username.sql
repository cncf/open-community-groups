-- Resolves a unique username by appending a numeric suffix when needed.
create or replace function resolve_unique_username(
    p_base_username text,
    p_excluded_user_id uuid default null
)
returns text as $$
declare
    v_suffix int;
    v_username text := p_base_username;
    v_username_exists boolean;
begin
    -- Check whether the base username is available
    select exists(
        select 1
        from "user"
        where username = v_username
        and (
            p_excluded_user_id is null
            or user_id <> p_excluded_user_id
        )
    ) into v_username_exists;

    -- If username exists, try with numeric suffixes from 2 to 99
    if v_username_exists then
        for v_suffix in 2..99 loop
            v_username := p_base_username || v_suffix;

            select exists(
                select 1
                from "user"
                where username = v_username
                and (
                    p_excluded_user_id is null
                    or user_id <> p_excluded_user_id
                )
            ) into v_username_exists;

            exit when not v_username_exists;
        end loop;

        if v_username_exists then
            raise exception 'unable to generate unique username: all variants from % to %99 are taken',
                p_base_username,
                p_base_username;
        end if;
    end if;

    return v_username;
end;
$$ language plpgsql;
