//! Database helpers shared by the OCG binaries.

use anyhow::{Context, Result, bail};
use openssl::{
    ssl::{SslConnector, SslMethod, SslVerifyMode},
    x509::X509,
};
use postgres_openssl::MakeTlsConnector;

use crate::config::{DbTlsConfig, DbTlsMode};

/// Builds the Postgres TLS connector from the configured verification policy.
///
/// # Errors
///
/// Returns an error when certificate verification is enabled without trust
/// roots or when the CA certificate bundle cannot be loaded.
pub fn tls_connector(tls: Option<&DbTlsConfig>) -> Result<MakeTlsConnector> {
    // Require explicit trust roots for certificate verification
    let mode = tls.map_or(DbTlsMode::None, |tls| tls.mode);
    let ca_cert = tls.and_then(|tls| tls.ca_cert.as_deref());
    if mode != DbTlsMode::None && ca_cert.is_none() {
        bail!("db.tls.ca_cert is required when db.tls.mode enables certificate verification");
    }

    // Configure certificate-chain verification for the selected TLS mode
    let mut builder =
        SslConnector::builder(SslMethod::tls()).context("error creating database TLS connector")?;
    builder.set_verify(match mode {
        DbTlsMode::None => SslVerifyMode::NONE,
        DbTlsMode::VerifyCa | DbTlsMode::VerifyFull => SslVerifyMode::PEER,
    });

    // Load every certificate in the configured PEM bundle into the trust store
    if let Some(ca_cert) = ca_cert {
        let certificates =
            X509::stack_from_pem(ca_cert.as_bytes()).context("db.tls.ca_cert is not valid PEM")?;
        if certificates.is_empty() {
            bail!("db.tls.ca_cert does not contain a certificate");
        }

        for certificate in certificates {
            builder
                .cert_store_mut()
                .add_cert(certificate)
                .context("error adding db.tls.ca_cert to the database trust store")?;
        }
    }

    // Disable only hostname verification for verify-ca connections
    let mut connector = MakeTlsConnector::new(builder.build());
    if mode == DbTlsMode::VerifyCa {
        connector.set_callback(|configuration, _| {
            configuration.set_verify_hostname(false);
            Ok(())
        });
    }

    Ok(connector)
}

#[cfg(test)]
mod tests {
    use std::{
        net::{SocketAddr, TcpListener},
        thread::{self, JoinHandle},
    };

    use openssl::{
        asn1::Asn1Time,
        bn::BigNum,
        hash::MessageDigest,
        pkey::{PKey, Private},
        rsa::Rsa,
        ssl::SslAcceptor,
        x509::{
            X509, X509NameBuilder,
            extension::{BasicConstraints, KeyUsage, SubjectAlternativeName},
        },
    };
    use tokio::net::TcpStream;
    use tokio_postgres::tls::{MakeTlsConnect, TlsConnect};

    use super::*;

    #[tokio::test]
    async fn test_tls_connector_handshake_follows_verification_mode() {
        // Setup a trusted CA and server certificates chaining to it or to an unknown CA
        let trusted_ca = test_certificate_authority();
        let trusted_server = test_server_certificate(&trusted_ca);
        let untrusted_server = test_server_certificate(&test_certificate_authority());

        // (case, mode, server chains to the trusted CA, hostname, handshake succeeds)
        let cases = [
            (
                "disabled verification, untrusted chain",
                None,
                false,
                "localhost",
                true,
            ),
            (
                "verify-ca, hostname mismatch",
                Some(DbTlsMode::VerifyCa),
                true,
                "db.example.test",
                true,
            ),
            (
                "verify-ca, untrusted chain",
                Some(DbTlsMode::VerifyCa),
                false,
                "localhost",
                false,
            ),
            (
                "verify-full, trusted chain and hostname",
                Some(DbTlsMode::VerifyFull),
                true,
                "localhost",
                true,
            ),
            (
                "verify-full, hostname mismatch",
                Some(DbTlsMode::VerifyFull),
                true,
                "db.example.test",
                false,
            ),
            (
                "verify-full, untrusted chain",
                Some(DbTlsMode::VerifyFull),
                false,
                "localhost",
                false,
            ),
        ];

        for (case, mode, trusted_chain, hostname, succeeds) in cases {
            // Setup the server and the connector for the verification mode
            let server_certificate = if trusted_chain {
                &trusted_server
            } else {
                &untrusted_server
            };
            let (address, server) = spawn_tls_server(server_certificate);
            let tls = mode.map(|mode| DbTlsConfig {
                mode,

                ca_cert: Some(certificate_pem(&trusted_ca)),
            });
            let connector = tls_connector(tls.as_ref()).unwrap();

            // Perform the TLS handshake against the test server
            let result = tls_handshake(connector, address, hostname).await;

            // Check the handshake outcome matches the verification policy
            assert_eq!(result.is_ok(), succeeds, "{case}: {result:?}");
            server.join().unwrap();
        }
    }

    #[test]
    fn test_tls_connector_rejects_invalid_trust_configuration() {
        let invalid_pem = "-----BEGIN CERTIFICATE-----\nnot base64!\n-----END CERTIFICATE-----\n";
        // (case, mode, ca_cert, expected error)
        let cases = [
            (
                "empty bundle",
                DbTlsMode::VerifyCa,
                Some(""),
                "db.tls.ca_cert does not contain a certificate",
            ),
            (
                "text without PEM markers",
                DbTlsMode::VerifyCa,
                Some("not a certificate"),
                "db.tls.ca_cert does not contain a certificate",
            ),
            (
                "malformed certificate",
                DbTlsMode::VerifyCa,
                Some(invalid_pem),
                "db.tls.ca_cert is not valid PEM",
            ),
            (
                "verification without trust roots",
                DbTlsMode::VerifyFull,
                None,
                "db.tls.ca_cert is required when db.tls.mode enables certificate verification",
            ),
        ];

        for (case, mode, ca_cert, expected) in cases {
            let tls = DbTlsConfig {
                mode,

                ca_cert: ca_cert.map(str::to_string),
            };

            let error = tls_connector(Some(&tls)).err().expect(case);

            assert_eq!(error.to_string(), expected, "{case}");
        }
    }

    // Helpers.

    /// Test certificate paired with its private key.
    struct TestCertificate {
        certificate: X509,
        key: PKey<Private>,
    }

    /// Returns the PEM encoding of the given test certificate.
    fn certificate_pem(certificate: &TestCertificate) -> String {
        String::from_utf8(certificate.certificate.to_pem().unwrap()).unwrap()
    }

    /// Spawns a TLS server that accepts a single handshake attempt.
    fn spawn_tls_server(server: &TestCertificate) -> (SocketAddr, JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let (certificate, key) = (server.certificate.clone(), server.key.clone());

        let handle = thread::spawn(move || {
            // Setup the acceptor with the server certificate and key
            let mut acceptor = SslAcceptor::mozilla_intermediate_v5(SslMethod::tls()).unwrap();
            acceptor.set_certificate(&certificate).unwrap();
            acceptor.set_private_key(&key).unwrap();
            let acceptor = acceptor.build();

            // Serve a single handshake; failures are asserted client-side
            let (stream, _) = listener.accept().unwrap();
            let _ = acceptor.accept(stream);
        });

        (address, handle)
    }

    /// Generates a self-signed certificate authority for handshake tests.
    fn test_certificate_authority() -> TestCertificate {
        // Setup deterministic certificate identity and validity
        let key = PKey::from_rsa(Rsa::generate(2048).unwrap()).unwrap();
        let mut name = X509NameBuilder::new().unwrap();
        name.append_entry_by_text("CN", "ocg-test-ca").unwrap();
        let name = name.build();
        let not_after = Asn1Time::days_from_now(1).unwrap();
        let not_before = Asn1Time::days_from_now(0).unwrap();
        let serial = BigNum::from_u32(1).unwrap().to_asn1_integer().unwrap();

        // Build and sign a minimal CA certificate
        let mut builder = X509::builder().unwrap();
        builder.set_version(2).unwrap();
        builder.set_serial_number(&serial).unwrap();
        builder.set_subject_name(&name).unwrap();
        builder.set_issuer_name(&name).unwrap();
        builder.set_pubkey(&key).unwrap();
        builder.set_not_after(&not_after).unwrap();
        builder.set_not_before(&not_before).unwrap();
        builder
            .append_extension(BasicConstraints::new().critical().ca().build().unwrap())
            .unwrap();
        builder
            .append_extension(KeyUsage::new().critical().key_cert_sign().build().unwrap())
            .unwrap();
        builder.sign(&key, MessageDigest::sha256()).unwrap();

        TestCertificate {
            certificate: builder.build(),
            key,
        }
    }

    /// Generates a localhost server certificate signed by the given CA.
    fn test_server_certificate(ca: &TestCertificate) -> TestCertificate {
        // Setup the server certificate identity and validity
        let key = PKey::from_rsa(Rsa::generate(2048).unwrap()).unwrap();
        let mut name = X509NameBuilder::new().unwrap();
        name.append_entry_by_text("CN", "localhost").unwrap();
        let name = name.build();
        let not_after = Asn1Time::days_from_now(1).unwrap();
        let not_before = Asn1Time::days_from_now(0).unwrap();
        let serial = BigNum::from_u32(2).unwrap().to_asn1_integer().unwrap();

        // Build and sign a localhost certificate with the CA key
        let mut builder = X509::builder().unwrap();
        builder.set_version(2).unwrap();
        builder.set_serial_number(&serial).unwrap();
        builder.set_subject_name(&name).unwrap();
        builder.set_issuer_name(ca.certificate.subject_name()).unwrap();
        builder.set_pubkey(&key).unwrap();
        builder.set_not_after(&not_after).unwrap();
        builder.set_not_before(&not_before).unwrap();
        let subject_alternative_name = SubjectAlternativeName::new()
            .dns("localhost")
            .build(&builder.x509v3_context(Some(&ca.certificate), None))
            .unwrap();
        builder.append_extension(subject_alternative_name).unwrap();
        builder.sign(&ca.key, MessageDigest::sha256()).unwrap();

        TestCertificate {
            certificate: builder.build(),
            key,
        }
    }

    /// Performs a TLS handshake against the given test server address.
    async fn tls_handshake(
        mut connector: MakeTlsConnector,
        address: SocketAddr,
        hostname: &str,
    ) -> Result<()> {
        let stream = TcpStream::connect(address).await?;
        let tls = <MakeTlsConnector as MakeTlsConnect<TcpStream>>::make_tls_connect(
            &mut connector,
            hostname,
        )?;
        tls.connect(stream)
            .await
            .map_err(|err| anyhow::anyhow!("TLS handshake failed: {err}"))?;

        Ok(())
    }
}
