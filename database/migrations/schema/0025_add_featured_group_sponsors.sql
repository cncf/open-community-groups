-- Adds featured placement to group sponsors.

-- Add the required featured state with its default
alter table group_sponsor
add column featured boolean not null default true;

-- Normalize existing sponsors explicitly for migration readability
update group_sponsor set featured = true;
