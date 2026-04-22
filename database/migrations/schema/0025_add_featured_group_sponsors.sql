alter table group_sponsor
add column featured boolean not null default true;

update group_sponsor set featured = true;
