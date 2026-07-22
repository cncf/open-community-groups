-- Apply safely to both the pre-baseline production schema and fresh baseline databases.
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

alter table "user" drop constraint if exists user_email_key;
alter table "user" drop constraint if exists user_username_key;
drop index if exists user_email_lower_idx;
drop index if exists user_username_lower_idx;

create unique index user_email_lower_idx on "user" (lower(email));
create unique index user_username_lower_idx on "user" (lower(username));
