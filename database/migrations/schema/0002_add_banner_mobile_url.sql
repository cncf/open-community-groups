-- Add banner_mobile_url column to alliance (mandatory, copy from banner_url).
alter table alliance add column banner_mobile_url text check (btrim(banner_mobile_url) <> '');
update alliance set banner_mobile_url = banner_url;
alter table alliance alter column banner_mobile_url set not null;

-- Add banner_mobile_url column to group (optional).
alter table "group" add column banner_mobile_url text check (btrim(banner_mobile_url) <> '');

-- Add banner_mobile_url column to event (optional).
alter table event add column banner_mobile_url text check (btrim(banner_mobile_url) <> '');
