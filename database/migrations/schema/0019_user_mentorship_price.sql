alter table "user"
add column if not exists mentorship_price text;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'user_mentorship_price_check'
    ) then
        alter table "user"
        add constraint user_mentorship_price_check
        check (btrim(mentorship_price) <> '');
    end if;
end;
$$;
