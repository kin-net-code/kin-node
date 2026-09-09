# Kin Identity, Fragment, and Proof Model

**Specification identifier:** `KIN-IDENTITY-FRAGMENTS/0.1`  
**Status:** Workshop draught; not implemented and not yet normative  
**Date:** 2026-09-09

## Abstract

This document sketches a transport-independent identity and proof model for Kin-Net.

A Kin identity is superordinate to its keys. It is a durable identifier for a verifiable, append-only identity lineage. Signing, encryption, control, recovery, and delegation keys are replaceable authorities associated with that lineage.

The fundamental durable content object is an immutable, content-addressed text fragment. A fragment is not a document. Ledger documents, Kin Packages, human-readable records, and other representations may contain or reference the same fragments in whatever compositions are useful. Recomposition does not change fragment identity or the proofs over those fragments.

## 1. Scope

This draught covers:

- Kin identities and identity inception;
- public-key identifiers and purpose-specific key authority;
- immutable hashed text fragments;
- signed assertions and identity proofs;
- key binding, refresh, rotation, suspension, revocation, and recovery;
- composition of fragments into Ledger documents and Kin Packages;
- the minimum responsibilities of an identity lifecycle toolkit.

This draught does not define:

- routing algorithms;
- endpoint discovery;
- a direct IP or VPN protocol;
- the Postcard transport protocol;
- an MCP binding;
- a final archive format or ZIP profile;
- a final canonical text encoding, hash suite, signature suite, or conflict-resolution policy.

## 2. Design principles

1. **Identity is durable; keys are replaceable.** Packages address identities, while cryptographic operations identify the particular keys used.
2. **Fragments are durable; documents are compositions.** A document has no intrinsic authority merely because it contains authoritative fragments.
3. **Authority is purpose-specific.** Possession of any one identity-associated key does not imply every authority held by that identity.
4. **History is append-only.** Identity state changes by adding signed events, never by rewriting earlier events.
5. **Revocation is explicit and monotonic.** Revocation removes future authority and cannot be silently undone. It does not rewrite historical signature validity.
6. **Meaningful composition is itself content.** If fragment selection, ordering, or roles carry meaning, the composition manifest is another hashed fragment.
7. **Transport does not define identity.** Zones, endpoints, relays, and routes may change or disappear without changing the destination identity.
8. **Verification is end-verifiable.** An intermediary may deliver or store proof material without being trusted to redefine it.

## 3. Terminology

### 3.1 Kin identity

A stable identifier plus the verifiable identity-event lineage rooted in its inception fragment.

### 3.2 Inception fragment

The immutable root fragment that establishes the initial identity-control policy. Its digest is the basis of the Kin identity identifier.

### 3.3 Key identifier

An immutable identifier derived from, or containing a fingerprint of, one public key. A private key is never an identifier and never appears in public identity material.

### 3.4 Fragment

An exact sequence of text bytes addressed by a cryptographic digest. The digest is an address of the fragment; it is not embedded recursively inside the bytes it identifies.

### 3.5 Assertion

A typed statement by an issuer about a subject, object, fragment, key, capability, or other referent.

### 3.6 Proof

Cryptographic evidence that an assertion or fragment was signed by one or more keys, together with sufficient identity-lineage context to determine whether those keys had the asserted authority.

A valid signature proves control of a key. It does not, by itself, prove that the key was authorized to act for an identity or for the relevant purpose.

### 3.7 Identity event

A fragment that advances an identity lineage by binding, rotating, suspending, revoking, delegating, or recovering authority.

### 3.8 Document

A presentation or composition containing or referencing fragments. Documents may be regenerated, reformatted, split, merged, archived, or transported without changing the contained fragments.

### 3.9 Ledger

An append-only ordered collection of content-addressed fragments and relationships. A Ledger document is a representation of Ledger material, not necessarily its semantic root.

### 3.10 Zone hint

Replaceable transport information suggesting a zone through which an identity might currently be reachable. It is not part of the identity and is not proof of identity ownership.

## 4. Identifier model

The provisional identifier families are:

```text
kin:id:<inception-fragment-multihash>
kin:key:<encoded-public-key-or-public-key-multihash>
kin:fragment:<multihash>
```

Their exact URI grammar and encoding remain open.

Conceptually:

```text
fragment_id = H(exact_fragment_bytes)
identity_id = kin:id:<digest of exact inception-fragment bytes>
key_id      = kin:key:<algorithm-qualified public-key identity>
```

The same identifier form may represent people, agents, roles, organisations, zones, nodes, services, or other principals. Whether an immutable identity `kind` is encoded in inception remains an open question.

### 4.1 UUIDs

UUIDs may be used as internal row identifiers, correlation identifiers, event nonces, or package identifiers. A bare UUID is not sufficient as a Kin identity root because uniqueness does not establish ownership or select an authoritative initial key binding.

## 5. Fragment model

### 5.1 Identity and integrity

A fragment is identified by the digest of its exact bytes. A verifier MUST reject supplied bytes that do not reproduce the claimed digest.

The eventual profile MUST specify:

- permitted character encoding;
- whether byte-order marks are permitted;
- newline treatment;
- Unicode normalization policy;
- canonicalization rules for structured text;
- supported digest algorithms and algorithm identifiers;
- maximum fragment size and parser limits.

Until that profile exists, examples in this draught are illustrative and are not interoperable test vectors.

### 5.2 Semantics

Metadata that changes a fragment's security meaning MUST either:

1. be present inside the hashed fragment; or
2. be bound by a separately hashed and signed assertion referencing the fragment.

File names, archive paths, MIME headers supplied only by a transport, and document layout MUST NOT silently change a fragment's authoritative interpretation.

### 5.3 Composition

Fragments MUST NOT be signed by ambiguous string concatenation. Meaningful composition uses an unambiguous manifest containing named or ordered fragment identifiers.

If composition itself carries authority, its manifest is another fragment:

```json
{
  "type": "kin.composition/1",
  "members": [
    {"role": "control-policy", "fragment": "kin:fragment:<digest-1>"},
    {"role": "initial-keys", "fragment": "kin:fragment:<digest-2>"},
    {"role": "recovery-policy", "fragment": "kin:fragment:<digest-3>"}
  ]
}
```

## 6. Identity inception

An identity begins with one canonical inception fragment. Its hash permanently names the identity.

An inception fragment SHOULD bind at least:

- protocol and format version;
- a high-entropy nonce;
- initial control key identifiers;
- the control signature threshold;
- permitted control operations;
- recovery policy or next-control-key commitments;
- algorithm-suite identifiers;
- any referenced policy fragments necessary to interpret inception.

Illustrative structure:

```json
{
  "type": "kin.identity.inception/1",
  "nonce": "<high-entropy value>",
  "control": {
    "threshold": 1,
    "keys": [
      "kin:key:z6MkgndstNvymG1VCR91AU38XZfsyVhGZFRumXVTgop8aBDQ"
    ]
  },
  "next_control_commitments": [
    "sha256:<digest-of-unexposed-next-key>"
  ],
  "policies": [
    "kin:fragment:<recovery-policy-digest>"
  ]
}
```

The resulting identity is:

```text
kin:id:<multihash of the exact inception fragment>
```

The inception fragment does not contain that resulting identifier or its own digest. Initial proof records reference and sign its digest, avoiding recursive hashing.

## 7. Keys and authority

Keys are immutable cryptographic objects with mutable authorization state.

Kin SHOULD support distinct key purposes, including:

- identity control and rotation;
- recovery;
- package signing;
- authentication;
- encryption or key agreement;
- capability invocation;
- capability delegation;
- witnessing or receipt signing;
- release, compiler, executor, or other operational roles.

One key MAY technically hold multiple purposes, but security profiles SHOULD prefer separation between control, signing, encryption, and recovery keys.

A key binding needs at least:

- identity identifier;
- key identifier and algorithm;
- authorized purpose or purposes;
- lifecycle state;
- event from which the binding is effective;
- optional expiry or usage constraints;
- authorizing identity-state reference.

The standard lifecycle states are:

```text
ACTIVE | SUSPENDED | REVOKED | EXPIRED | UNKNOWN
```

`REVOKED` is terminal. `UNKNOWN` MUST fail closed for operations whose policy requires positive authorization.

## 8. Identity-event lineage

An identity changes through signed, append-only identity-event fragments.

An event SHOULD contain:

```json
{
  "type": "kin.identity.event/1",
  "identity": "kin:id:<inception-digest>",
  "sequence": 4,
  "previous": "kin:fragment:<previous-event-digest>",
  "operation": "rotate-keys",
  "changes": [],
  "authority_state": "kin:fragment:<authorizing-state-digest>"
}
```

Ordering MUST be established by sequence numbers and predecessor hashes, not by unauthenticated wall-clock timestamps.

Supported operations are expected to include:

- bind a key;
- refresh an operational key;
- rotate control keys;
- suspend a key or delegation;
- revoke a key, delegation, assertion, or session;
- declare expiry;
- update recovery commitments;
- recover control;
- delegate or withdraw authority.

### 8.1 Operational refresh

Refreshing a key means generating a new key, publishing an authorized binding or rotation event, optionally allowing a bounded overlap, and then expiring or revoking the old key. Existing key material is never overwritten in place.

### 8.2 Control rotation

Control rotation changes which keys may advance the identity lineage. A production profile SHOULD use precommitted successor keys, threshold recovery, witnesses, or another explicit fork-resolution mechanism. A current-key signature alone may be insufficient after compromise because both the legitimate controller and attacker could create plausible successor events.

### 8.3 Recovery

Recovery is a distinct authority declared before ordinary control is lost. If no valid control or recovery path remains, the identity persists but becomes orphaned. Implementations MUST NOT silently rebind it through database administration.

### 8.4 Historical verification

Revocation prevents future authority; it does not automatically invalidate signatures created while a key was valid. Historical verification therefore requires the verifier to establish:

- the relevant identity state;
- whether the signing key was authorized for the stated purpose at that state;
- whether the event or assertion can be placed before suspension, expiry, or revocation under the applicable evidence policy.

Trusted time is optional and policy-dependent. Ledger ordering, witness receipts, or external timestamp evidence may provide stronger chronology than a self-declared timestamp.

## 9. Assertions and proofs

### 9.1 Assertion fragments

An assertion is structured text that identifies its semantic context. It SHOULD include:

- protocol version and domain;
- assertion type;
- issuer identity;
- subject identity or fragment;
- predicate or declared relationship;
- object value or referenced fragment identifiers;
- required signing purpose;
- identity-state reference;
- nonce, sequence, or other replay context;
- optional validity interval;
- optional predecessor, supersession, or revocation target;
- schema or policy references where necessary.

Assertions may express, among other things:

```text
Identity A authorizes Key K for package signing.
Identity A revokes Key J after identity event 17.
Identity A claims the display name “Pioneer”.
Zone Z accepts delivery for Identity A until T.
Identity A delegates capability C to Identity B.
```

Names and delivery hints are claims about identities. They are not identity identifiers.

### 9.2 Signature proof fragments

A detached proof fragment may identify:

```json
{
  "type": "kin.signature-proof/1",
  "target": "kin:fragment:<signed-fragment-digest>",
  "signer": "kin:id:<signer-identity-digest>",
  "key": "kin:key:<signing-key-id>",
  "purpose": "identity-assertion",
  "authority_state": "kin:fragment:<identity-state-digest>",
  "algorithm": "<signature-suite>",
  "signature": "<encoded-signature>"
}
```

The final profile MUST specify domain separation and the exact bytes signed. A likely construction signs a protocol-domain tag plus the target fragment identifier and necessary proof context.

A proof fragment has its own digest like any other fragment. It never signs or hashes itself.

### 9.3 Proof closure

To accept an assertion, a verifier needs either:

- local access to the necessary identity lineage and policies; or
- a supplied proof bundle containing sufficient fragments to validate the assertion offline.

The minimum portable proof-bundle format remains open.

## 10. Documents, Ledgers, and packages

### 10.1 Documents

A document may inline or reference fragments. Its formatting, title, path, explanatory prose, and arrangement may change without changing fragment identifiers.

A document signature covers only what its signed manifest commits to. Merely placing two fragments in the same document does not create an authoritative relationship between them.

### 10.2 Ledger documents

A Ledger document may present identity history, assertions, proofs, receipts, or other fragments for humans or machines. If a Ledger entry's membership and order are authoritative, the entry manifest MUST itself be a hashed fragment and SHOULD link to its predecessor or parents.

The Ledger may therefore be understood as an append-only graph or sequence of fragment relationships. Rendered Ledger documents are views over that material.

### 10.3 Kin Packages

A `.kin` package may carry:

- fragments;
- proof fragments;
- identity-lineage fragments;
- Ledger documents;
- MCP messages;
- artifacts;
- other independently typed protocols.

Package and archive digests protect a particular assembly or wire representation. They do not replace fragment identifiers and do not define identity.

The semantic package manifest should address stable identities:

```json
{
  "from": "kin:id:<sender-inception-digest>",
  "to": ["kin:id:<recipient-inception-digest>"]
}
```

Signature metadata identifies the actual signing `kin:key:…`. An encryption wrapper identifies the actual recipient encryption or key-agreement `kin:key:…`.

Delivery state, endpoints, retry policy, routes, and mediator state are not intrinsic package content.

### 10.4 Zone hints

Transport may separately submit:

```json
{
  "destination": "kin:id:<recipient-inception-digest>",
  "via": ["kin:id:<zone-inception-digest>"]
}
```

Forwarders may replace or add `via` hints without changing the destination identity or signed package content.

## 11. Verification procedure

A verifier evaluating an identity assertion should, at minimum:

1. Recompute every supplied fragment digest.
2. Recompute the identity identifier from the inception fragment.
3. Validate the inception proof under the declared inception control policy.
4. Reconstruct the relevant identity-event lineage using sequence and predecessor references.
5. Reject malformed, missing, conflicting, or unauthorized state transitions according to policy.
6. Validate the assertion signature over the precisely defined signed input.
7. Establish that the identified key was authorized for the required purpose at the referenced identity state.
8. Apply suspension, revocation, expiry, delegation, threshold, witness, and chronology rules.
9. Validate any semantic composition manifest on which the assertion depends.
10. Return a result that distinguishes cryptographic validity, identity authority, policy acceptance, and unresolved state.

A verifier MUST NOT collapse these distinct conclusions into “the signature matches.”

## 12. Identity lifecycle toolkit

Kin-Net will require a transport-independent identity lifecycle library and CLI. It should emit and verify fragments rather than modifying identity history in place.

Provisional command surface:

```text
kin-id incept
kin-id inspect
kin-id verify
kin-id key generate
kin-id key bind
kin-id key prepare-next
kin-id key refresh
kin-id key rotate
kin-id key suspend
kin-id key revoke
kin-id assert
kin-id assertion revoke
kin-id recover
kin-id export-proof
```

The toolkit needs separable components for:

- key custody and signer backends;
- fragment canonicalization and hashing;
- inception construction;
- identity-event construction;
- assertion and proof construction;
- identity resolution and verification;
- proof-closure export;
- safe human inspection.

Private-key custody MUST be isolated from identity-event logic. Signer backends should eventually support encrypted files, operating-system keystores, PKCS#11 or HSM devices, hardware tokens, and remote signers without changing the event model.

## 13. Security invariants

1. Private keys never appear in identifiers, fragments intended for publication, documents, or packages.
2. Exact signed bytes, hash algorithms, key algorithms, and domain tags are explicit.
3. A signature proves key control, not identity authority.
4. Identity authority is derived from a valid lineage rooted in inception.
5. Key purposes are checked independently.
6. Revocation is append-only and non-reversible.
7. Historical validity is evaluated against historical identity state rather than the latest key set alone.
8. Arbitrary document co-location does not create a signed relationship.
9. Semantically meaningful composition is explicitly manifested and hashed.
10. Names, zones, endpoints, and routes cannot replace cryptographic identity identifiers.
11. Parser limits, path safety, archive limits, and denial-of-service controls are required in later packaging profiles.
12. No identifier's mere possession grants authority.

## 14. Open decisions

The following remain deliberately unsettled:

1. Exact canonical structured-text format and Unicode policy.
2. Default and permitted digest algorithms.
3. Public-key and multihash textual encodings.
4. Signature container and algorithm suites, including whether to profile COSE.
5. Encryption and key-wrapping suites, including whether to profile HPKE.
6. Required next-key commitment, recovery, threshold, and witness rules.
7. Fork detection and conflict-resolution policy.
8. Trusted-time and historical-validity evidence.
9. Proof-bundle and resolver interfaces.
10. Privacy and selective-disclosure treatment for identity lineages.
11. Whether identity `kind` is immutable inception data or a later assertion.
12. Which assertion predicates and key purposes are standardized initially.
13. Relationship between the general fragment Ledger and specialized identity-event lineages.
14. Whether `kin:id`, `kin:key`, and `kin:fragment` become registered URI schemes, URNs, or Kin-local identifiers.

## 15. Related work

This draught intentionally borrows concepts without yet adopting an entire external protocol:

- [W3C Decentralized Identifiers](https://www.w3.org/TR/did/) separates stable subjects from purpose-specific verification methods.
- [KERI](https://trustoverip.github.io/kswg-keri-specification/) uses self-certifying persistent identifiers and append-only key-event logs with key pre-rotation.
- [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785) defines a JSON canonicalization scheme worth evaluating for structured text.
- [RFC 9052](https://www.rfc-editor.org/rfc/rfc9052) defines COSE signing and encryption structures worth evaluating for proof containers.
- [RFC 9180](https://www.rfc-editor.org/rfc/rfc9180) defines HPKE, a candidate foundation for recipient encryption.
- [RFC 9562](https://www.rfc-editor.org/rfc/rfc9562) defines UUIDs and their security limitations.

## 16. Compact statement of the model

> A Kin identity is the verifiable append-only lineage rooted at the digest of an immutable inception fragment. Public keys are immutable, purpose-specific authorities bound to that identity by signed identity events. All durable semantic content is carried by hashed text fragments. Assertions and proofs bind fragments to identities and authority states. Documents, Ledgers, packages, and transports may compose and carry those fragments without redefining them.

