-- Returns an unexpired authentication session by identifier.
create or replace function get_auth_session(p_auth_session_id text)
returns table (data jsonb, expires_at timestamptz) as $$
    select s.data, s.expires_at
    from auth_session s
    where s.auth_session_id = p_auth_session_id
    and s.expires_at > current_timestamp;
$$ language sql stable;
