-- Inserts a baseline registered user row with placeholder plumbing.
create or replace function fx_user(
    p_user_id uuid,
    p_overrides jsonb default '{}'::jsonb
)
returns void as $$
begin
    perform fx_insert_row('"user"', jsonb_build_object(
        'auth_hash', 'fixture-auth-hash',
        'email', 'fixture-user-' || p_user_id || '@fixture.test',
        'email_verified', true,
        'user_id', p_user_id,
        'username', 'fixture-user-' || p_user_id
    ) || p_overrides);
end;
$$ language plpgsql;
