//! Data Integrity document wrapper with spec-compliant boolean canonicalization.

use std::{borrow::Cow, hash::Hash};

use serde::{Deserialize, Serialize};
use ssi_claims_core::ValidateClaims;
use ssi_data_integrity::DataIntegrityDocument;
use ssi_json_ld::{
    Expandable, ExpandedDocument, Indexed, JsonLdError, JsonLdNodeObject, JsonLdObject,
    JsonLdTypes, Loader, Node, Object,
    object::{Literal, Value as LdValue},
    syntax::Context,
};
use ssi_rdf::{
    Interpretation, LdEnvironment, LinkedDataResource, LinkedDataSubject, Vocabulary, VocabularyMut,
};

/// Data Integrity document whose typed booleans canonicalize per JSON-LD.
///
/// The `json-ld` crate ignores the context-declared datatype of typed boolean
/// literals when it serializes RDF terms and hardcodes the `http://` XSD
/// boolean IRI, while the Open Badges 3.0.3 context types `hashed` in the
/// `https://` XSD namespace. External verifiers keep the declared datatype, so
/// proofs computed over the crate's quads fail outside OCG. This wrapper
/// rewrites every typed boolean literal into its canonical lexical string form
/// after expansion, which preserves the declared datatype and yields the same
/// RDF literal mandated by the JSON-LD to RDF algorithm.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(transparent)]
pub(super) struct CredentialDocument(pub(super) DataIntegrityDocument);

impl Expandable for CredentialDocument {
    type Error = JsonLdError;

    type Expanded<I: Interpretation, V: Vocabulary>
        = ExpandedDocument<V::Iri, V::BlankId>
    where
        I: Interpretation,
        V: VocabularyMut,
        V::Iri: LinkedDataResource<I, V> + LinkedDataSubject<I, V>,
        V::BlankId: LinkedDataResource<I, V> + LinkedDataSubject<I, V>;

    async fn expand_with<I, V>(
        &self,
        ld: &mut LdEnvironment<V, I>,
        loader: &impl Loader,
    ) -> Result<Self::Expanded<I, V>, Self::Error>
    where
        I: Interpretation,
        V: VocabularyMut,
        V::Iri: Clone + Eq + Hash + LinkedDataResource<I, V> + LinkedDataSubject<I, V>,
        V::BlankId: Clone + Eq + Hash + LinkedDataResource<I, V> + LinkedDataSubject<I, V>,
    {
        // Expand the inner document, then repair typed boolean literals
        let expanded = self.0.expand_with(ld, loader).await?;
        Ok(stringify_typed_booleans(expanded))
    }
}

impl JsonLdNodeObject for CredentialDocument {
    /// [`JsonLdNodeObject::json_ld_type`].
    fn json_ld_type(&'_ self) -> JsonLdTypes<'_> {
        self.0.json_ld_type()
    }
}

impl JsonLdObject for CredentialDocument {
    /// [`JsonLdObject::json_ld_context`].
    fn json_ld_context(&'_ self) -> Option<Cow<'_, Context>> {
        self.0.json_ld_context()
    }
}

impl<E, P> ValidateClaims<E, P> for CredentialDocument {
    /// [`ValidateClaims::validate_claims`].
    fn validate_claims(&self, env: &E, proof: &P) -> ssi_claims_core::ClaimsValidity {
        self.0.validate_claims(env, proof)
    }
}

/// Rewrites one expanded object tree, replacing typed boolean literals.
fn patch_object<T, B>(object: &mut Indexed<Object<T, B>>)
where
    T: Eq + Hash,
    B: Eq + Hash,
{
    match object.inner_mut() {
        Object::List(list) => {
            for item in list.iter_mut() {
                patch_object(item);
            }
        }
        Object::Node(node) => patch_object_node(node),
        Object::Value(LdValue::Literal(literal, Some(_))) => {
            if let Literal::Boolean(value) = literal {
                let lexical = if *value { "true" } else { "false" };
                *literal = Literal::String(lexical.into());
            }
        }
        Object::Value(_) => {}
    }
}

/// Rewrites every object reachable from one expanded node.
fn patch_object_node<T, B>(node: &mut Node<T, B>)
where
    T: Eq + Hash,
    B: Eq + Hash,
{
    // Walk direct and reverse property values
    for (_, objects) in node.properties_mut().iter_mut() {
        for object in objects.iter_mut() {
            patch_object(object);
        }
    }
    if let Some(reverse_properties) = node.reverse_properties_mut() {
        for (_, nodes) in reverse_properties.iter_mut() {
            for reverse_node in nodes.iter_mut() {
                patch_object_node(reverse_node.inner_mut());
            }
        }
    }

    // Rebuild the named graph and included sets with patched members
    if let Some(graph) = node.graph_entry_mut() {
        *graph = std::mem::take(graph)
            .into_iter()
            .map(|mut object| {
                patch_object(&mut object);
                object
            })
            .collect();
    }
    if let Some(included) = node.included_entry_mut() {
        *included = std::mem::take(included)
            .into_iter()
            .map(|mut included_node| {
                patch_object_node(included_node.inner_mut());
                included_node
            })
            .collect();
    }
}

/// Replaces typed boolean literals with their canonical lexical string form.
///
/// The rewrite keeps the datatype IRI attached by expansion, so the resulting
/// RDF literal is identical to the one required by the JSON-LD specification.
/// Untyped booleans are left for the crate's spec-correct default handling.
fn stringify_typed_booleans<T, B>(document: ExpandedDocument<T, B>) -> ExpandedDocument<T, B>
where
    T: Eq + Hash,
    B: Eq + Hash,
{
    let mut patched = ExpandedDocument::default();
    for mut object in document.into_objects() {
        patch_object(&mut object);
        patched.insert(object);
    }
    patched
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    use ssi_rdf::AnyLdEnvironment;

    use super::{super::contexts, CredentialDocument, Expandable, LdEnvironment};

    #[tokio::test]
    async fn test_typed_boolean_keeps_context_datatype_in_canonical_quads() {
        // Setup a minimal credential fragment with the boolean hashed flag
        let document: CredentialDocument = serde_json::from_value(json!({
            "@context": [
                "https://www.w3.org/ns/credentials/v2",
                "https://purl.imsglobal.org/spec/ob/v3p0/context-3.0.3.json"
            ],
            "type": ["VerifiableCredential", "OpenBadgeCredential"],
            "credentialSubject": {
                "type": ["AchievementSubject"],
                "identifier": [{
                    "type": "IdentityObject",
                    "hashed": true,
                    "identityHash": "sha256$00",
                    "identityType": "emailAddress",
                    "salt": "00"
                }]
            }
        }))
        .unwrap();

        // Expand and canonicalize through the closed context loader
        let loader = contexts::loader().unwrap();
        let mut ld = LdEnvironment::default();
        let expanded = document.expand_with(&mut ld, &loader).await.unwrap();
        let quads = ld.canonical_form_of(&expanded).unwrap().concat();

        // Check the context-declared https XSD boolean datatype is preserved
        assert!(quads.contains("\"true\"^^<https://www.w3.org/2001/XMLSchema#boolean>"));
        assert!(!quads.contains("<http://www.w3.org/2001/XMLSchema#boolean>"));
    }
}
