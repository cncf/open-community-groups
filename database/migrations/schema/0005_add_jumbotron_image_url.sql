-- Adds jumbotron image URL field to community table
alter table community add column jumbotron_image_url text check (jumbotron_image_url <> '');
