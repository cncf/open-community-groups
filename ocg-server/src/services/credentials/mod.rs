//! External credentials issuer client (CertDirectory adapter).

pub(crate) mod client;

pub(crate) use client::{CredentialsClient, CredentialsError, ListedCredential, friendly};
