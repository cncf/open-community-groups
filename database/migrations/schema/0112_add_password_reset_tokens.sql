-- Adds password reset tokens and the password-reset notification kind.

create table password_reset_token (
    token_hash bytea primary key check (octet_length(token_hash) = 32),
    created_at timestamptz default current_timestamp not null,
    user_id uuid not null unique references "user" on delete cascade
);

create index password_reset_token_created_at_idx on password_reset_token (created_at);

insert into notification_kind (name) values ('password-reset');
