alter table mock_interview_match
add column if not exists interviewer_rating int;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'mock_interview_match_interviewer_rating_check'
    ) then
        alter table mock_interview_match
        add constraint mock_interview_match_interviewer_rating_check
        check (interviewer_rating is null or interviewer_rating between 1 and 5);
    end if;
end $$;
