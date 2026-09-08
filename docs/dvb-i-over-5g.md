# DVB-I over 5G: what integration would require

An assessment of what it would take to carry the DVB-I services these repositories publish over a
5G system, rather than over unicast HTTP as the live demo does today.

Written 2026-09-08 against the documents named below. It is an engineering assessment, not a
statement of DVB or 3GPP positions, and it should be checked against those bodies before being
relied on for anything beyond planning.

## The documents

| Document | Status | What it gives us |
|---|---|---|
| ETSI TS 103 770 V1.2.1 (2024-09) | published standard | the DVB-I service list format, and clause 9.3, carriage in an MBMS system |
| ETSI TR 103 972 V1.1.1 (2023-07) | technical report, informative | "DVB-I service delivery over 5G Systems; Deployment Guidelines": architectures, call flows, and explicit lists of gaps |
| DVB A177r8 (draft TS 103 770 V1.3.1, June 2026) | draft | the successor to the published standard |

TR 103 972 is a **Technical Report**: deployment guidance, not a specification. Its value here is
that clauses 6.2.4 and 6.3.4 enumerate what was missing from the standards, which is precisely the
question. Being from 2023-07, it predates the published TS 103 770 V1.2.1 by more than a year, and
part of its gap list has since been closed. Which parts, below.

## What is already specified, and is more than most people expect

TS 103 770 V1.2.1 clause 9.3 covers carriage of DVB-I in an MBMS system normatively, and it fits
the component split these repositories already have.

**Service classes are defined.** Clause 9.3.1, table 106 gives three identifiers:
`urn:dvb:metadata:serviceClass:DVB-I_Service_List:1`, `...DVB-I_Content_Guide:1` and
`...DVB-I_Service_Instance:1`, for a service list document, content guide documents, and the media
assets of a service instance respectively. The clause requires that
`userServiceDescription@serviceClass` be present and carry the appropriate one.

This closes TR 103 972 clause 6.2.4's gap that "a service class filter for DVB-I services is needed
to be defined by DVB in order to select DVB-I services". It was open when the report was written
and is not open now.

**The client model matches what we have built.** Clause 9.3.3 puts the DVB-I client in the role of
an MBMS-Aware Application which invokes an MBMS Client: it starts the service announcement channel,
acquires the service list from an MBMS user service of the right class when it has no unicast
connection, and subscribes to notifications so it picks up new versions of those documents.

That is the same split as `rt-mbs-client` (the MBS client, holding the announcement channel and the
reception) and `rt-mbs-application` (the MBS-aware application driving it over a local API). A
DVB-I receiver would occupy the second role.

## What is still missing

**There is no delivery parameters type for MBMS or 5G Broadcast.** A service instance chooses among
`DVBTDeliveryParameters`, `DVBSDeliveryParameters`, `DVBCDeliveryParameters`,
`RTSPDeliveryParameters`, `MulticastTSDeliveryParameters`, `DASHDeliveryParameters`,
`SATIPDeliveryParameters`, `IdentifierBasedDeliveryParameters` (clauses 5.5.18.1 to 5.5.18.8) or the
`OtherDeliveryParameters` extension point. None of them is MBMS.

Clause 9.3.3 nonetheless speaks of "a DVB-I service instance with an mbms:// locator", and that
phrase is the only occurrence of `mbms://` in the document: the behaviour is specified while the
element that would carry the locator is not. TR 103 972 clause 6.2.4 says an extension is needed so
that a service instance can refer to a 5G Broadcast or MBMS URL with delivery parameters of its own,
and notes it could be defined either in TS 103 770 or in an MBMS or 5G Broadcast specification.

Checked directly: neither TS 103 770 V1.2.1 nor the A177r8 draft of V1.3.1 contains the strings
"5G Broadcast", "5GMS" or "ServiceAccessInformation" anywhere. This gap is open in the published
standard and remains open in its draft successor.

**Nothing carries 5G Media Streaming access information.** TR 103 972 clause 6.3.4 identifies that
service instance metadata needs to convey baseline 5GMS Service Access Information, suggesting a new
element used alongside `DASHDeliveryParameters`, with zero or more permitted because the information
may be available from several 5GMSd AF instances. It identifies further gaps on the 3GPP side, in
the M7 interface of TS 126 512, which are not ours to close.

**Instance selection is under-signalled for hybrid use.** TR 103 972 clause 6.4.3.3 recommends
against signalling a 5G Broadcast service as ordinary DASH delivery, because existing clients may
assume DASH means unicast, and prefers a distinct instance type. Clause 6.4.4.4 notes that where the
same content is offered on two instances, new signalling is needed to say that the two are identical
and time-aligned so a client may combine them.

## What these repositories already provide

| Piece | Where | Relevance |
|---|---|---|
| Service list generation with an extension point | `rt-dvb-i-application-provider` | `OtherDeliveryParameters` with an `xsi:type` is already how HLS is signalled here, following TS 103 770 annex G.2.2. The same mechanism is what a 5G Broadcast instance would use. |
| A receiver that already handles unplayable instance types | `rt-dvb-i-application` | It parses DVB-T/S/C instances and lists those services with a badge rather than dropping them, which is the behaviour an unsupported 5G instance needs. |
| An MBS client and an MBS-aware application | `rt-mbs-client`, `rt-mbs-application` | Exactly the two roles clause 9.3.3 describes, with a local API between them. |
| Service announcement and object delivery | `rt-mbs-function`, `rt-mbs-transport-function` | The provisioning and transport side, already carrying DASH presentations over FLUTE. |

The pieces are unusually well matched. What is missing is the signalling that joins them.

## What would need building

In the order that yields something demonstrable soonest.

1. **Decide and document the delivery signalling.** Since no standard element exists, a
   demonstration has to choose one, and must be explicit that it is a local extension rather than a
   specified one. `OtherDeliveryParameters` with a private `xsi:type` carrying the MBMS service
   locator is the option TR 103 972 clause 6.4.3.3 effectively points at, and the option it warns
   against is dressing it up as ordinary DASH delivery. Whatever is chosen should be recorded in the
   conformance record as an extension, so it is never mistaken for conformance.

2. **Emit it from the provider.** A new instance type alongside the existing DASH one, so a service
   is offered on both unicast and 5G, which is the hybrid case of TR 103 972 clause 6.4.

3. **Publish the service list itself over MBMS.** Clause 9.3.1 already defines the service class for
   this, so the provisioning side is specified: a user service of class `DVB-I_Service_List:1`
   carrying the list document, which the MBS stack can already deliver as an object.

4. **Teach the receiver the new instance type.** It should list such a service, and where an MBS
   client is reachable, select it by asking that client to start reception. In a browser receiver
   this means talking to the MBS application's local API rather than fetching a URL, which is a
   larger change than the previous three.

5. **Only then, the 5GMS path.** It depends on gaps that are 3GPP's to close, not ours, and the
   report says so.

Steps 1 to 3 are achievable with what is in these repositories now. Step 4 is the substantial one.
Step 5 is blocked on standards work.

## What this assessment does not establish

- Whether DVB intends to close these gaps in V1.3.1 or later. The draft does not, but a draft is not
  a plan of record, and the question belongs to DVB.
- Anything about the 3GPP-side gaps in TR 103 972 clause 6.3.4 beyond repeating them: they concern
  TS 126 501 and TS 126 512, which were not consulted here.
- Whether any of this interoperates. Nothing described above has been built or tested.
