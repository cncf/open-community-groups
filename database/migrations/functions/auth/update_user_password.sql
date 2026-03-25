-- update_user_password updates a user's password and rotates its auth hash.
create or replace function update_user_password(
    p_actor_user_id uuid,
    p_password text
)
returns void as $$
begin
    -- Update the password and rotate the auth hash
    update "user"
    set
        auth_hash = encode(gen_random_bytes(32), 'hex'),
        password = p_password
    where user_id = p_actor_user_id;

    -- Track the password update
    perform insert_audit_log(
        'user_password_updated',
        p_actor_user_id,
        'user',
        p_actor_user_id
    );
end;
$$ language plpgsql;
