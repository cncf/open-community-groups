update site
set favicon_url = '/static/images/favicon.png'
where title = 'GOUP Alliance'
and favicon_url is null;
