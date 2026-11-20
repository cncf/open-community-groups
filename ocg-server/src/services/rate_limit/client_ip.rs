//! Client IP resolution and normalisation into limiting keys.

use std::{
    fmt,
    net::{IpAddr, Ipv4Addr, Ipv6Addr},
};

use anyhow::Result;
use axum::http::{HeaderMap, HeaderName, HeaderValue};
use ipnet::IpNet;

use crate::config::ClientIpConfig;

#[cfg(test)]
mod tests;

/// Longest header element accepted as an address, in bytes.
const MAX_ENTRY_LEN: usize = 64;

/// Resolves the client of a request from its peer address and headers.
#[derive(Clone, Debug)]
pub(super) struct ClientIpResolver {
    /// Configured source of the client address.
    source: ResolverSource,
}

impl ClientIpResolver {
    /// Builds a resolver from the validated client IP configuration.
    pub(super) fn new(cfg: &ClientIpConfig) -> Result<Self> {
        let source = match cfg {
            ClientIpConfig::Header(header_cfg) => ResolverSource::Header {
                header_name: header_cfg.header_name()?,
                trusted_networks: header_cfg.trusted_networks()?,
            },
            ClientIpConfig::Peer(_) => ResolverSource::Peer,
        };

        Ok(Self { source })
    }

    /// Resolves the client of a request.
    ///
    /// The peer source uses the peer address. The header source reads the
    /// header only when the trust list is empty or the peer is trusted, then
    /// walks its elements right to left across all lines: with an empty trust
    /// list the rightmost element is the client, otherwise trusted elements are
    /// skipped and the first untrusted one is the client. An element that does
    /// not parse stops the walk, so a client can never choose its own key.
    pub(super) fn resolve(&self, peer: Option<IpAddr>, headers: &HeaderMap) -> Resolution {
        // Use the peer as the client for the peer source
        let (header_name, trusted_networks) = match &self.source {
            ResolverSource::Header {
                header_name,
                trusted_networks,
            } => (header_name, trusted_networks),
            ResolverSource::Peer => {
                return match peer {
                    Some(peer) => Resolution::resolved(None, peer, ResolvedVia::Peer),
                    None => Resolution::unresolved(None, UnresolvedReason::NoPeerInfo),
                };
            }
        };

        // Read the header only from a trusted peer when a trust list is configured
        if !trusted_networks.is_empty() {
            let Some(peer) = peer else {
                return Resolution::unresolved(None, UnresolvedReason::NoPeerInfo);
            };
            if !self.is_trusted_proxy(peer) {
                return Resolution::unresolved(None, UnresolvedReason::UntrustedPeer);
            }
        }

        // Collect the header lines and count their non-empty elements
        let lines: Vec<&HeaderValue> = headers.get_all(header_name).iter().collect();
        if lines.is_empty() {
            return Resolution::unresolved(None, UnresolvedReason::HeaderMissing);
        }
        let entries = lines.iter().map(|line| header_elements(line).count()).sum();
        let shape = |left_of_client| HeaderShape {
            entries,
            left_of_client,
            lines: lines.len(),
        };
        if entries == 0 {
            return Resolution::unresolved(Some(shape(false)), UnresolvedReason::HeaderMissing);
        }

        // Walk the elements right to left across all lines
        let elements = lines.iter().rev().flat_map(|line| header_elements(line).rev());
        for (position, element) in elements.enumerate() {
            // Stop at an element that does not parse instead of skipping past it
            let Some(ip) = parse_entry(element) else {
                return Resolution::unresolved(
                    Some(shape(false)),
                    UnresolvedReason::UnparseableEntry,
                );
            };

            // Select the rightmost element, or the first one outside the trust list
            if trusted_networks.is_empty() || !self.is_trusted_proxy(ip) {
                let left_of_client = position + 1 < entries;
                return Resolution::resolved(Some(shape(left_of_client)), ip, ResolvedVia::Header);
            }
        }

        // Report a header made only of trusted proxy addresses
        Resolution::unresolved(Some(shape(false)), UnresolvedReason::AllEntriesTrusted)
    }

    /// Returns whether the address is inside a trusted proxy network.
    ///
    /// The check uses the full canonical address. It is always false for the
    /// peer source, which has no trust list.
    pub(super) fn is_trusted_proxy(&self, ip: IpAddr) -> bool {
        match &self.source {
            ResolverSource::Header {
                trusted_networks, ..
            } => {
                let ip = ip.to_canonical();
                trusted_networks.iter().any(|network| network.contains(&ip))
            }
            ResolverSource::Peer => false,
        }
    }

    /// Returns the configured source as its `snake_case` config value.
    pub(super) fn source_name(&self) -> &'static str {
        match &self.source {
            ResolverSource::Header { .. } => "header",
            ResolverSource::Peer => "peer",
        }
    }

    /// Returns the number of configured trusted proxy networks.
    pub(super) fn trusted_proxy_count(&self) -> usize {
        match &self.source {
            ResolverSource::Header {
                trusted_networks, ..
            } => trusted_networks.len(),
            ResolverSource::Peer => 0,
        }
    }
}

/// Configured source of the client address.
#[derive(Clone, Debug)]
enum ResolverSource {
    /// Client address read from a request header set by a proxy.
    Header {
        /// Header carrying the client address.
        header_name: HeaderName,
        /// Proxy networks skipped when walking the header.
        trusted_networks: Vec<IpNet>,
    },
    /// Client address taken from the TCP peer.
    Peer,
}

/// Key a client is limited by: a full IPv4 address or an IPv6 /64 prefix.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub(crate) enum ClientKey {
    /// Full IPv4 address.
    V4([u8; 4]),
    /// First 64 bits of an IPv6 address.
    V6Prefix([u8; 8]),
}

impl ClientKey {
    /// Returns the key with client-identifying bits hidden, for log lines.
    ///
    /// IPv4 keys hide the last octet (`203.0.113.x`) and IPv6 keys show only
    /// their first three groups (`2001:db8:1234::`).
    pub(super) fn masked(self) -> String {
        match self {
            ClientKey::V4([a, b, c, _]) => format!("{a}.{b}.{c}.x"),
            ClientKey::V6Prefix(prefix) => {
                let mut octets = [0; 16];
                octets[..6].copy_from_slice(&prefix[..6]);
                Ipv6Addr::from(octets).to_string()
            }
        }
    }
}

impl From<IpAddr> for ClientKey {
    /// Builds the key of an address after unwrapping IPv4-mapped IPv6 forms.
    fn from(ip: IpAddr) -> Self {
        match ip.to_canonical() {
            IpAddr::V4(ip) => ClientKey::V4(ip.octets()),
            IpAddr::V6(ip) => {
                let mut prefix = [0; 8];
                prefix.copy_from_slice(&ip.octets()[..8]);
                ClientKey::V6Prefix(prefix)
            }
        }
    }
}

impl fmt::Display for ClientKey {
    /// Formats the key in full: the IPv4 address or the IPv6 /64 network.
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ClientKey::V4(octets) => write!(f, "{}", Ipv4Addr::from(*octets)),
            ClientKey::V6Prefix(prefix) => {
                let mut octets = [0; 16];
                octets[..8].copy_from_slice(prefix);
                write!(f, "{}/64", Ipv6Addr::from(octets))
            }
        }
    }
}

/// Result of resolving the client of one request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct Resolution {
    /// Selected client, or the reason no client was selected.
    pub outcome: Result<ResolvedClient, UnresolvedReason>,

    /// Shape of the client IP header, present when at least one line was read.
    pub header: Option<HeaderShape>,
}

impl Resolution {
    /// Builds a resolution that selected the given address as the client.
    fn resolved(header: Option<HeaderShape>, ip: IpAddr, via: ResolvedVia) -> Self {
        let ip = ip.to_canonical();
        Self {
            outcome: Ok(ResolvedClient {
                internal: is_internal(ip),
                key: ClientKey::from(ip),
                via,
            }),
            header,
        }
    }

    /// Builds a resolution that selected no client.
    fn unresolved(header: Option<HeaderShape>, reason: UnresolvedReason) -> Self {
        Self {
            outcome: Err(reason),
            header,
        }
    }
}

/// Shape of the client IP header of one request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct HeaderShape {
    /// Number of non-empty elements across all lines.
    pub entries: usize,
    /// Whether elements remain to the left of the selected client.
    pub left_of_client: bool,
    /// Number of header lines.
    pub lines: usize,
}

/// Client selected for a request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct ResolvedClient {
    /// Whether the selected address is private, loopback, link-local, CGNAT
    /// or IPv6 unique-local.
    pub internal: bool,
    /// Key the client is limited by.
    pub key: ClientKey,
    /// Where the client address came from.
    pub via: ResolvedVia,
}

/// Where a resolved client address came from.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub(crate) enum ResolvedVia {
    /// The configured client IP header.
    Header,
    /// The TCP peer address.
    Peer,
}

/// Why no client was selected for a request.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub(crate) enum UnresolvedReason {
    /// Every header element is a trusted proxy address.
    AllEntriesTrusted,
    /// The header is absent or has no non-empty element.
    HeaderMissing,
    /// The request carries no peer address.
    NoPeerInfo,
    /// The walk reached a header element that is not an address.
    UnparseableEntry,
    /// The peer is outside every trusted proxy network.
    UntrustedPeer,
}

/// Returns whether the address is private, loopback, link-local, CGNAT
/// (`100.64.0.0/10`) or IPv6 unique-local.
pub(super) fn is_internal(ip: IpAddr) -> bool {
    match ip.to_canonical() {
        IpAddr::V4(ip) => {
            let [first, second, ..] = ip.octets();
            let is_cgnat = first == 100 && second & 0b1100_0000 == 0b0100_0000;
            ip.is_private() || ip.is_loopback() || ip.is_link_local() || is_cgnat
        }
        IpAddr::V6(ip) => ip.is_loopback() || ip.is_unicast_link_local() || ip.is_unique_local(),
    }
}

/// Returns the address masked like a client key, for log lines.
pub(super) fn mask_ip(ip: IpAddr) -> String {
    ClientKey::from(ip).masked()
}

/// Splits one header line into its trimmed, non-empty elements.
fn header_elements(line: &HeaderValue) -> impl DoubleEndedIterator<Item = &[u8]> {
    line.as_bytes()
        .split(|byte| *byte == b',')
        .map(trim_element)
        .filter(|element| !element.is_empty())
}

/// Returns whether the text is a decimal TCP port.
fn is_port(port: &str) -> bool {
    !port.is_empty()
        && port.bytes().all(|byte| byte.is_ascii_digit())
        && port.parse::<u16>().is_ok()
}

/// Parses one header element into a canonical address.
///
/// Accepts a bare address, an IPv4 address with a port and a bracketed IPv6
/// address with an optional port. An unbracketed IPv6 address is parsed as a
/// bare address, so one followed by a port does not parse. Elements longer
/// than [`MAX_ENTRY_LEN`], invalid UTF-8, `unknown`, obfuscated identifiers,
/// zone ids and quoted values do not parse.
fn parse_entry(element: &[u8]) -> Option<IpAddr> {
    // Reject oversized elements and bytes that are not UTF-8
    if element.len() > MAX_ENTRY_LEN {
        return None;
    }
    let element = str::from_utf8(element).ok()?;

    // Parse the address in its bracketed, bare or IPv4-with-port form
    let ip = if let Some(rest) = element.strip_prefix('[') {
        let (address, after) = rest.split_once(']')?;
        if !after.is_empty() && !is_port(after.strip_prefix(':')?) {
            return None;
        }
        IpAddr::V6(address.parse::<Ipv6Addr>().ok()?)
    } else if let Ok(ip) = element.parse::<IpAddr>() {
        ip
    } else {
        let (address, port) = element.split_once(':')?;
        if !is_port(port) {
            return None;
        }
        IpAddr::V4(address.parse::<Ipv4Addr>().ok()?)
    };

    Some(ip.to_canonical())
}

/// Trims spaces and tabs around a header element.
fn trim_element(mut element: &[u8]) -> &[u8] {
    while let [b' ' | b'\t', rest @ ..] = element {
        element = rest;
    }
    while let [rest @ .., b' ' | b'\t'] = element {
        element = rest;
    }
    element
}
