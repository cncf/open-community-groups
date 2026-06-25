-- Add a unique index for Linux Foundation OIDC identity reconciliation.
create unique index user_linuxfoundation_identity_idx
on "user" (
    (provider #>> '{linuxfoundation,issuer}'),
    (provider #>> '{linuxfoundation,subject}')
)
where provider #>> '{linuxfoundation,issuer}' is not null
and provider #>> '{linuxfoundation,issuer}' <> ''
and provider #>> '{linuxfoundation,subject}' is not null
and provider #>> '{linuxfoundation,subject}' <> '';
