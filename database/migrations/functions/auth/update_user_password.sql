-- update_user_password updates a user's password and rotates its auth hash.
create or replace function update_user_password(
    p_user_id uuid,
    p_password text
)
returns void as $$
    update "user"
    set
        auth_hash = encode(gen_random_bytes(32), 'hex'),
        password = p_password
    where user_id = p_user_id;
$$ language sql;
