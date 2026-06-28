alter table "user"
add column if not exists substack_url text,
add column if not exists youtube_url text;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'user_substack_url_check'
    ) then
        alter table "user"
        add constraint user_substack_url_check
        check (btrim(substack_url) <> '');
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conname = 'user_youtube_url_check'
    ) then
        alter table "user"
        add constraint user_youtube_url_check
        check (btrim(youtube_url) <> '');
    end if;
end $$;
