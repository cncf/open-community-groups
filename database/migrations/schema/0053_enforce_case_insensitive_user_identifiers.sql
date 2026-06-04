-- Enforce case-insensitive uniqueness for user emails and usernames.

-- Refuse to change the schema until existing data can satisfy the new
-- case-insensitive uniqueness rules.
do $$
begin
    if exists (
        select 1
        from "user"
        group by lower(email)
        having count(*) > 1
    ) then
        raise exception 'case-insensitive duplicate user emails must be resolved before migration 0053';
    end if;

    if exists (
        select 1
        from "user"
        group by lower(username)
        having count(*) > 1
    ) then
        raise exception 'case-insensitive duplicate usernames must be resolved before migration 0053';
    end if;
end;
$$;

-- Drop the case-sensitive unique constraints and the non-unique lowercase
-- indexes that backed lookups.
alter table "user" drop constraint user_email_key;
alter table "user" drop constraint user_username_key;
drop index user_email_lower_idx;
drop index user_username_lower_idx;

-- Recreate the lowercase indexes as unique so identifiers that differ only in
-- case cannot coexist.
create unique index user_email_lower_idx on "user" (lower(email));
create unique index user_username_lower_idx on "user" (lower(username));
