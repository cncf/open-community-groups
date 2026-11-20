use std::net::IpAddr;

use axum::http::{HeaderMap, HeaderName, HeaderValue};

use crate::config::{ClientIpConfig, ClientIpHeaderConfig, ClientIpPeerConfig};

use super::{
    ClientIpResolver, ClientKey, HeaderShape, Resolution, ResolvedClient, ResolvedVia,
    UnresolvedReason, is_internal, mask_ip, parse_entry,
};

#[test]
fn test_client_ip_resolver_new_rejects_invalid_config() {
    // Setup labeled invalid configurations with the expected error
    let cases = [
        (
            "empty header name",
            header_cfg("", &[]),
            "server.rate_limit.client_ip.header cannot be empty",
        ),
        (
            "forwarded header",
            header_cfg("forwarded", &[]),
            "server.rate_limit.client_ip.header cannot be 'forwarded': RFC 7239 syntax is not supported",
        ),
        (
            "invalid trusted proxy",
            header_cfg("x-forwarded-for", &["not-a-network"]),
            "server.rate_limit.client_ip.trusted_proxies entry 'not-a-network' is not a valid CIDR or IP address",
        ),
    ];

    // Check each configuration is rejected with its error
    for (case, cfg, expected) in cases {
        assert_eq!(
            ClientIpResolver::new(&cfg).unwrap_err().to_string(),
            expected,
            "{case}"
        );
    }
}

#[test]
fn test_client_ip_resolver_resolve_header_element_forms() {
    // Setup a resolver without trusted proxies and labeled header lines
    let resolver = resolver(&header_cfg("x-forwarded-for", &[]));
    let long_left = format!("{}, 203.0.113.7", "1".repeat(65));
    let long_right = format!("203.0.113.7, {}", "1".repeat(65));
    let cases = [
        (
            "unparseable rightmost element",
            "203.0.113.7, unknown",
            unresolved(Some(shape(2, false, 1)), UnresolvedReason::UnparseableEntry),
        ),
        (
            "element over 64 bytes on the left is not read",
            long_left.as_str(),
            resolved_header("203.0.113.7", false, shape(2, true, 1)),
        ),
        (
            "rightmost element over 64 bytes",
            long_right.as_str(),
            unresolved(Some(shape(2, false, 1)), UnresolvedReason::UnparseableEntry),
        ),
        (
            "unbracketed ipv6 address followed by a port",
            "2001:db8::1:46532",
            unresolved(Some(shape(1, false, 1)), UnresolvedReason::UnparseableEntry),
        ),
        (
            "ipv4 element with a port",
            "203.0.113.7:5678",
            resolved_header("203.0.113.7", false, shape(1, false, 1)),
        ),
        (
            "bracketed ipv6 element with a port",
            "[2001:db8:1234:5678::1]:443",
            resolved_header("2001:db8:1234:5678::1", false, shape(1, false, 1)),
        ),
        (
            "ipv4-mapped element is keyed as ipv4",
            "::ffff:203.0.113.7",
            resolved_header("203.0.113.7", false, shape(1, false, 1)),
        ),
        (
            "internal rightmost element",
            "203.0.113.7, 100.64.0.1",
            resolved_header("100.64.0.1", true, shape(2, true, 1)),
        ),
    ];

    // Check each header line resolves as expected
    for (case, line, expected) in cases {
        assert_eq!(
            resolver.resolve(Some(ip("10.0.0.1")), &headers("x-forwarded-for", &[line])),
            expected,
            "{case}"
        );
    }
}

#[test]
fn test_client_ip_resolver_resolve_header_source_with_trusted_proxies() {
    // Setup a resolver with trusted proxies and labeled requests
    let resolver = resolver(&header_cfg(
        "x-forwarded-for",
        &["10.0.0.0/8", "192.0.2.10", "2001:db8:ffff::/48"],
    ));
    let cases = [
        (
            "no peer information leaves the header unread",
            None,
            vec!["203.0.113.7"],
            unresolved(None, UnresolvedReason::NoPeerInfo),
        ),
        (
            "untrusted peer leaves the header unread",
            Some("198.51.100.1"),
            vec!["203.0.113.7"],
            unresolved(None, UnresolvedReason::UntrustedPeer),
        ),
        (
            "trusted peer with no header",
            Some("10.0.0.1"),
            vec![],
            unresolved(None, UnresolvedReason::HeaderMissing),
        ),
        (
            "trusted peer with only empty elements",
            Some("10.0.0.1"),
            vec![" , ,\t,"],
            unresolved(Some(shape(0, false, 1)), UnresolvedReason::HeaderMissing),
        ),
        (
            "rightmost untrusted element is the client",
            Some("10.0.0.1"),
            vec!["203.0.113.7"],
            resolved_header("203.0.113.7", false, shape(1, false, 1)),
        ),
        (
            "trusted elements are skipped",
            Some("10.0.0.1"),
            vec!["203.0.113.7, 192.0.2.10, 10.1.2.3"],
            resolved_header("203.0.113.7", false, shape(3, false, 1)),
        ),
        (
            "spoofed entries on the left are ignored",
            Some("10.0.0.1"),
            vec!["198.51.100.77, 192.0.2.1, 203.0.113.7, 10.1.2.3"],
            resolved_header("203.0.113.7", false, shape(4, true, 1)),
        ),
        (
            "unparseable element in the middle is never skipped",
            Some("10.0.0.1"),
            vec!["203.0.113.7, garbage, 10.1.2.3"],
            unresolved(Some(shape(3, false, 1)), UnresolvedReason::UnparseableEntry),
        ),
        (
            "every element trusted",
            Some("10.0.0.1"),
            vec!["10.1.2.3, 192.0.2.10"],
            unresolved(
                Some(shape(2, false, 1)),
                UnresolvedReason::AllEntriesTrusted,
            ),
        ),
        (
            "walk continues across header lines",
            Some("10.0.0.1"),
            vec!["198.51.100.77, 203.0.113.7", "10.1.2.3", "192.0.2.10"],
            resolved_header("203.0.113.7", false, shape(4, true, 3)),
        ),
        (
            "ipv4-mapped peer is trusted by its ipv4 network",
            Some("::ffff:10.0.0.1"),
            vec!["203.0.113.7"],
            resolved_header("203.0.113.7", false, shape(1, false, 1)),
        ),
        (
            "ipv4-mapped element is trusted by its ipv4 network",
            Some("10.0.0.1"),
            vec!["203.0.113.7, [::ffff:10.1.2.3]:443"],
            resolved_header("203.0.113.7", false, shape(2, false, 1)),
        ),
        (
            "trust check uses the full ipv6 address",
            Some("2001:db8:ffff::1"),
            vec!["2001:db8:1234:5678::1, 2001:db8:ffff:1::2"],
            resolved_header("2001:db8:1234:5678::1", false, shape(2, false, 1)),
        ),
        (
            "internal client selected when a proxy is missing from the list",
            Some("10.0.0.1"),
            vec!["203.0.113.7, 172.16.0.5"],
            resolved_header("172.16.0.5", true, shape(2, true, 1)),
        ),
    ];

    // Check each request resolves as expected
    for (case, peer, lines, expected) in cases {
        assert_eq!(
            resolver.resolve(peer.map(ip), &headers("x-forwarded-for", &lines)),
            expected,
            "{case}"
        );
    }
}

#[test]
fn test_client_ip_resolver_resolve_header_source_without_trusted_proxies() {
    // Setup a resolver without trusted proxies and labeled requests
    let resolver = resolver(&header_cfg("x-forwarded-for", &[]));
    let cases = [
        (
            "no header",
            Some("10.0.0.1"),
            vec![],
            unresolved(None, UnresolvedReason::HeaderMissing),
        ),
        (
            "only empty elements",
            Some("10.0.0.1"),
            vec![",, ,"],
            unresolved(Some(shape(0, false, 1)), UnresolvedReason::HeaderMissing),
        ),
        (
            "single element is the client",
            Some("10.0.0.1"),
            vec!["203.0.113.7"],
            resolved_header("203.0.113.7", false, shape(1, false, 1)),
        ),
        (
            "peer is not checked",
            None,
            vec!["203.0.113.7"],
            resolved_header("203.0.113.7", false, shape(1, false, 1)),
        ),
        (
            "rightmost element is the client and spoofed entries are ignored",
            Some("10.0.0.1"),
            vec!["198.51.100.77, 192.0.2.1, 203.0.113.7"],
            resolved_header("203.0.113.7", false, shape(3, true, 1)),
        ),
        (
            "empty elements and trailing commas are dropped",
            Some("10.0.0.1"),
            vec![" , 198.51.100.77,, \t203.0.113.7\t ,, "],
            resolved_header("203.0.113.7", false, shape(2, true, 1)),
        ),
        (
            "rightmost element of the last line is the client",
            Some("10.0.0.1"),
            vec!["198.51.100.77", "192.0.2.1, 203.0.113.7"],
            resolved_header("203.0.113.7", false, shape(3, true, 2)),
        ),
        (
            "empty last line is skipped",
            Some("10.0.0.1"),
            vec!["198.51.100.77, 203.0.113.7", " "],
            resolved_header("203.0.113.7", false, shape(2, true, 2)),
        ),
    ];

    // Check each request resolves as expected
    for (case, peer, lines, expected) in cases {
        assert_eq!(
            resolver.resolve(peer.map(ip), &headers("x-forwarded-for", &lines)),
            expected,
            "{case}"
        );
    }
}

#[test]
fn test_client_ip_resolver_resolve_ignores_non_ascii_element_left_of_client() {
    // Setup a header line with invalid UTF-8 left of a valid client
    let resolver = resolver(&header_cfg("x-forwarded-for", &[]));
    let mut headers = HeaderMap::new();
    headers.append(
        "x-forwarded-for",
        HeaderValue::from_bytes(b"\xff\xfe\xc3\xa9, 203.0.113.7").unwrap(),
    );

    // Resolve the client
    let resolution = resolver.resolve(Some(ip("10.0.0.1")), &headers);

    // Check the rightmost element is the client
    assert_eq!(
        resolution,
        resolved_header("203.0.113.7", false, shape(2, true, 1))
    );
}

#[test]
fn test_client_ip_resolver_resolve_non_ascii_rightmost_element_is_unparseable() {
    // Setup a header line whose rightmost element is not UTF-8
    let resolver = resolver(&header_cfg("x-forwarded-for", &[]));
    let mut headers = HeaderMap::new();
    headers.append(
        "x-forwarded-for",
        HeaderValue::from_bytes(b"203.0.113.7, \xff\xfe").unwrap(),
    );

    // Resolve the client
    let resolution = resolver.resolve(Some(ip("10.0.0.1")), &headers);

    // Check the walk stops at the unparseable element
    assert_eq!(
        resolution,
        unresolved(Some(shape(2, false, 1)), UnresolvedReason::UnparseableEntry)
    );
}

#[test]
fn test_client_ip_resolver_resolve_peer_source() {
    // Setup a peer source resolver and labeled peers with the expected resolution
    let resolver = resolver(&ClientIpConfig::Peer(ClientIpPeerConfig {}));
    let cases = [
        (
            "no peer information",
            None,
            unresolved(None, UnresolvedReason::NoPeerInfo),
        ),
        (
            "ipv4 peer is the client and the header is ignored",
            Some("203.0.113.7"),
            resolved_peer("203.0.113.7", false),
        ),
        (
            "ipv4-mapped peer is keyed as ipv4",
            Some("::ffff:203.0.113.7"),
            resolved_peer("203.0.113.7", false),
        ),
        (
            "ipv6 peer is keyed by its /64",
            Some("2001:db8:1234:5678::1"),
            resolved_peer("2001:db8:1234:5678:ffff::", false),
        ),
        (
            "internal peer",
            Some("192.168.1.10"),
            resolved_peer("192.168.1.10", true),
        ),
    ];

    // Check each peer resolves as expected while a header is present
    for (case, peer, expected) in cases {
        assert_eq!(
            resolver.resolve(
                peer.map(ip),
                &headers("x-forwarded-for", &["198.51.100.77"])
            ),
            expected,
            "{case}"
        );
    }
}

#[test]
fn test_client_ip_resolver_resolve_single_value_headers() {
    // Setup labeled single-value header configurations and lines with the expected resolution
    let cases = [
        (
            "x-real-ip without trusted proxies",
            header_cfg("x-real-ip", &[]),
            "x-real-ip",
            vec!["203.0.113.7"],
            resolved_header("203.0.113.7", false, shape(1, false, 1)),
        ),
        (
            "x-real-ip with a trusted peer",
            header_cfg("x-real-ip", &["10.0.0.0/8"]),
            "x-real-ip",
            vec!["203.0.113.7"],
            resolved_header("203.0.113.7", false, shape(1, false, 1)),
        ),
        (
            "cf-connecting-ip ipv6 value",
            header_cfg("cf-connecting-ip", &[]),
            "cf-connecting-ip",
            vec!["2001:db8:1234:5678::1"],
            resolved_header("2001:db8:1234:5678::1", false, shape(1, false, 1)),
        ),
        (
            "cf-connecting-ip rightmost of several values",
            header_cfg("cf-connecting-ip", &[]),
            "cf-connecting-ip",
            vec!["198.51.100.77, 203.0.113.7"],
            resolved_header("203.0.113.7", false, shape(2, true, 1)),
        ),
        (
            "configured header absent while another header is present",
            header_cfg("cf-connecting-ip", &[]),
            "x-forwarded-for",
            vec!["203.0.113.7"],
            unresolved(None, UnresolvedReason::HeaderMissing),
        ),
    ];

    // Check each request resolves as expected
    for (case, cfg, header_name, lines, expected) in cases {
        assert_eq!(
            resolver(&cfg).resolve(Some(ip("10.0.0.1")), &headers(header_name, &lines)),
            expected,
            "{case}"
        );
    }
}

#[test]
fn test_client_ip_resolver_trust_accessors() {
    // Setup labeled configurations with the expected source, proxy count and trusted addresses
    let cases = [
        (
            "peer source",
            ClientIpConfig::Peer(ClientIpPeerConfig {}),
            "peer",
            0,
            vec![("10.0.0.1", false)],
        ),
        (
            "header source without trusted proxies",
            header_cfg("x-forwarded-for", &[]),
            "header",
            0,
            vec![("10.0.0.1", false)],
        ),
        (
            "header source with trusted proxies",
            header_cfg("x-forwarded-for", &["10.0.0.0/8", "2001:db8::1"]),
            "header",
            2,
            vec![
                ("10.0.0.1", true),
                ("::ffff:10.0.0.1", true),
                ("11.0.0.1", false),
                ("2001:db8::1", true),
                ("2001:db8::2", false),
            ],
        ),
    ];

    // Check each resolver reports its source and trust list
    for (case, cfg, source_name, trusted_proxy_count, addresses) in cases {
        let resolver = resolver(&cfg);
        assert_eq!(resolver.source_name(), source_name, "{case}");
        assert_eq!(
            resolver.trusted_proxy_count(),
            trusted_proxy_count,
            "{case}"
        );
        for (address, is_trusted) in addresses {
            assert_eq!(
                resolver.is_trusted_proxy(ip(address)),
                is_trusted,
                "{case}: {address}"
            );
        }
    }
}

#[test]
fn test_client_key_display_shows_full_key() {
    // Setup labeled addresses with the expected key display
    let cases = [
        ("ipv4 address", "203.0.113.7", "203.0.113.7"),
        ("ipv4-mapped address", "::ffff:203.0.113.7", "203.0.113.7"),
        (
            "ipv6 address",
            "2001:db8:1234:5678:9abc::1",
            "2001:db8:1234:5678::/64",
        ),
        ("ipv6 loopback", "::1", "::/64"),
    ];

    // Check each key displays in full
    for (case, address, expected) in cases {
        assert_eq!(ClientKey::from(ip(address)).to_string(), expected, "{case}");
    }
}

#[test]
fn test_client_key_from_ip_groups_ipv6_by_64_bit_prefix() {
    // Setup labeled address pairs with whether they share a key
    let cases = [
        (
            "same /64",
            "2001:db8:1234:5678::1",
            "2001:db8:1234:5678:ffff:ffff:ffff:ffff",
            true,
        ),
        (
            "different /64 in the same /48",
            "2001:db8:1234:5678::1",
            "2001:db8:1234:5679::1",
            false,
        ),
        (
            "ipv4-mapped and plain ipv4",
            "::ffff:203.0.113.7",
            "203.0.113.7",
            true,
        ),
        (
            "different ipv4 addresses in the same /24",
            "203.0.113.7",
            "203.0.113.8",
            false,
        ),
    ];

    // Check each pair shares a key only when expected
    for (case, first, second, same_key) in cases {
        assert_eq!(
            ClientKey::from(ip(first)) == ClientKey::from(ip(second)),
            same_key,
            "{case}"
        );
    }
}

#[test]
fn test_client_key_masked_hides_client_bits() {
    // Setup labeled keys with the expected masked display
    let cases = [
        ("ipv4 key", ClientKey::V4([203, 0, 113, 7]), "203.0.113.x"),
        (
            "ipv6 key",
            ClientKey::V6Prefix([0x20, 0x01, 0x0d, 0xb8, 0x12, 0x34, 0x56, 0x78]),
            "2001:db8:1234::",
        ),
        (
            "ipv6 key with a zero third group",
            ClientKey::V6Prefix([0x20, 0x01, 0x0d, 0xb8, 0, 0, 0x56, 0x78]),
            "2001:db8::",
        ),
    ];

    // Check each key is masked as expected
    for (case, key, expected) in cases {
        assert_eq!(key.masked(), expected, "{case}");
    }
}

#[test]
fn test_is_internal() {
    // Setup labeled addresses with whether they are internal
    let cases = [
        ("ipv4 private 10/8", "10.1.2.3", true),
        ("ipv4 private 172.16/12", "172.31.255.255", true),
        ("ipv4 private 192.168/16", "192.168.0.1", true),
        ("ipv4 loopback", "127.0.0.1", true),
        ("ipv4 link-local", "169.254.1.1", true),
        ("ipv4 cgnat lower bound", "100.64.0.0", true),
        ("ipv4 cgnat upper bound", "100.127.255.255", true),
        ("ipv4 below cgnat", "100.63.255.255", false),
        ("ipv4 above cgnat", "100.128.0.0", false),
        ("ipv4 outside 172.16/12", "172.32.0.1", false),
        ("ipv4 public", "203.0.113.7", false),
        ("ipv4-mapped private", "::ffff:10.1.2.3", true),
        ("ipv4-mapped public", "::ffff:203.0.113.7", false),
        ("ipv6 loopback", "::1", true),
        ("ipv6 link-local", "fe80::1", true),
        ("ipv6 unique-local fc00::/7 lower half", "fc00::1", true),
        (
            "ipv6 unique-local fc00::/7 upper half",
            "fd12:3456::1",
            true,
        ),
        ("ipv6 global", "2001:db8::1", false),
    ];

    // Check each address is classified as expected
    for (case, address, expected) in cases {
        assert_eq!(is_internal(ip(address)), expected, "{case}");
    }
}

#[test]
fn test_mask_ip() {
    // Setup labeled addresses with the expected masked display
    let cases = [
        ("ipv4 address", "203.0.113.7", "203.0.113.x"),
        ("ipv4-mapped address", "::ffff:203.0.113.7", "203.0.113.x"),
        ("ipv6 address", "2001:db8:1234:5678::1", "2001:db8:1234::"),
        (
            "ipv6 address with a zero group",
            "2001:db8:0:5678::1",
            "2001:db8::",
        ),
    ];

    // Check each address is masked as expected
    for (case, address, expected) in cases {
        assert_eq!(mask_ip(ip(address)), expected, "{case}");
    }
}

#[test]
fn test_parse_entry() {
    // Setup labeled elements with the expected parse result
    let cases: [(&str, &[u8], Option<&str>); 29] = [
        ("bare ipv4", b"203.0.113.7", Some("203.0.113.7")),
        ("ipv4 with a port", b"203.0.113.7:5678", Some("203.0.113.7")),
        ("bare ipv6", b"2001:db8::1", Some("2001:db8::1")),
        ("uppercase ipv6", b"2001:DB8::1", Some("2001:db8::1")),
        ("bracketed ipv6", b"[2001:db8::1]", Some("2001:db8::1")),
        (
            "bracketed ipv6 with a port",
            b"[2001:db8::1]:443",
            Some("2001:db8::1"),
        ),
        (
            "ipv4-mapped ipv6",
            b"::ffff:203.0.113.7",
            Some("203.0.113.7"),
        ),
        (
            "bracketed ipv4-mapped ipv6 with a port",
            b"[::ffff:203.0.113.7]:443",
            Some("203.0.113.7"),
        ),
        (
            "element of exactly 64 bytes",
            b"[0000:0000:0000:0000:0000:0000:0000:0001]:0000000000000000000443",
            Some("::1"),
        ),
        (
            "element over 64 bytes",
            b"[0000:0000:0000:0000:0000:0000:0000:0001]:00000000000000000000443",
            None,
        ),
        ("invalid utf-8", b"\xff203.0.113.7", None),
        ("unknown", b"unknown", None),
        ("obfuscated identifier", b"_hidden", None),
        ("obfuscated identifier with a port", b"_hidden:80", None),
        ("ipv6 zone id", b"fe80::1%eth0", None),
        (
            "bracketed ipv6 zone id with a port",
            b"[fe80::1%2]:443",
            None,
        ),
        ("quoted ipv4", b"\"203.0.113.7\"", None),
        ("quoted bracketed ipv6", b"\"[2001:db8::1]:443\"", None),
        ("unbracketed ipv6 with a port", b"2001:db8::1:46532", None),
        ("bracketed ipv4", b"[203.0.113.7]", None),
        ("ipv4 with an empty port", b"203.0.113.7:", None),
        ("ipv4 with a signed port", b"203.0.113.7:+80", None),
        ("ipv4 with an oversized port", b"203.0.113.7:65536", None),
        ("ipv4 with two ports", b"203.0.113.7:80:81", None),
        (
            "bracketed ipv6 without a closing bracket",
            b"[2001:db8::1",
            None,
        ),
        (
            "bracketed ipv6 with trailing text",
            b"[2001:db8::1]x443",
            None,
        ),
        ("ipv4 with a leading zero", b"203.0.113.07", None),
        ("hostname", b"example.com", None),
        ("empty element", b"", None),
    ];

    // Check each element parses as expected
    for (case, element, expected) in cases {
        assert_eq!(parse_entry(element), expected.map(ip), "{case}");
    }
}

// Helpers.

/// Builds a header source configuration.
fn header_cfg(header: &str, trusted_proxies: &[&str]) -> ClientIpConfig {
    ClientIpConfig::Header(ClientIpHeaderConfig {
        header: header.to_string(),
        trusted_proxies: trusted_proxies.iter().map(ToString::to_string).collect(),
    })
}

/// Builds a header map with one line per value under the given name.
fn headers(name: &str, lines: &[&str]) -> HeaderMap {
    let name = HeaderName::from_bytes(name.as_bytes()).unwrap();
    let mut headers = HeaderMap::new();
    for line in lines {
        headers.append(name.clone(), HeaderValue::from_str(line).unwrap());
    }
    headers
}

/// Parses an address literal.
fn ip(address: &str) -> IpAddr {
    address.parse().unwrap()
}

/// Builds an expected resolution selected from the header.
fn resolved_header(address: &str, internal: bool, header: HeaderShape) -> Resolution {
    Resolution {
        outcome: Ok(ResolvedClient {
            internal,
            key: ClientKey::from(ip(address)),
            via: ResolvedVia::Header,
        }),
        header: Some(header),
    }
}

/// Builds an expected resolution selected from the peer.
fn resolved_peer(address: &str, internal: bool) -> Resolution {
    Resolution {
        outcome: Ok(ResolvedClient {
            internal,
            key: ClientKey::from(ip(address)),
            via: ResolvedVia::Peer,
        }),
        header: None,
    }
}

/// Builds a resolver from a configuration.
fn resolver(cfg: &ClientIpConfig) -> ClientIpResolver {
    ClientIpResolver::new(cfg).unwrap()
}

/// Builds an expected header shape.
fn shape(entries: usize, left_of_client: bool, lines: usize) -> HeaderShape {
    HeaderShape {
        entries,
        left_of_client,
        lines,
    }
}

/// Builds an expected unresolved resolution.
fn unresolved(header: Option<HeaderShape>, reason: UnresolvedReason) -> Resolution {
    Resolution {
        outcome: Err(reason),
        header,
    }
}
