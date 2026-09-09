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

## Gap by gap: what has closed since the report

TR 103 972 was published in 2023-07 and assessed 5G Media Streaming against **Release 16**. The
current specification is Release 18, and the client APIs have since been restructured into a
separate document. Most of its 5GMS gaps are closed.

Checked 2026-09-09 against ETSI TS 103 770 V1.2.1, DVB A177r8 (draft V1.3.1), ETSI TS 126 512
V18.6.0 (2025-07) and ETSI TS 126 510 V19.1.0 (2026-02). Three gaps could not be checked because
they belong to documents not consulted here, and are marked as such rather than guessed at.

### 5G Broadcast scenario, TR clause 6.2.4

| # | Gap | Owner | Status |
|---|---|---|---|
| 1 | How `Keep updated interval` and `Periodic update interval` should be configured is unclear | TS 129 116 | **not checked** |
| 2 | A 5G Broadcast Receiver is not required to support simultaneous reception of more than one user service | TS 103 720 | **not checked** |
| 3 | Possible gap in the stage 3 xMB-C API for notifying the BM-SC of updates | TS 129 116 | **not checked** |
| 4 | A service class filter for DVB-I services needs defining by DVB | DVB | **closed** |
| 5 | A service instance cannot refer to a 5G Broadcast or MBMS URL | DVB or 3GPP | **open** |

**Gap 4 is closed.** TS 103 770 V1.2.1 clause 9.3.1 table 106 defines three service class
identifiers, `urn:dvb:metadata:serviceClass:DVB-I_Service_List:1`, `...DVB-I_Content_Guide:1` and
`...DVB-I_Service_Instance:1`, and the clause requires `userServiceDescription@serviceClass` to
carry the appropriate one. That is exactly the filter the report asked for, and it arrived in the
issue published a year after the report.

**Gap 5 is open, and stays open in the draft.** The delivery parameter choice offers eight types
(clauses 5.5.18.1 to 5.5.18.8) plus the `OtherDeliveryParameters` extension point, none of them
MBMS. Clause 9.3.3 nonetheless describes what a client does with "a service instance with an
mbms:// locator", the only occurrence of that scheme in the document. Neither V1.2.1 nor A177r8
contains the string "5G Broadcast", "5GMS" or "ServiceAccessInformation" anywhere.

### 5G Media Streaming scenario, TR clause 6.3.4

| # | Gap | Owner | Status |
|---|---|---|---|
| 1 | Service instance metadata needs 5GMS Service Access Information | DVB, or 3GPP | **open** on the DVB side |
| 2 | Playlist entry needs the same | DVB, or 3GPP | **open** on the DVB side |
| 3 | No means to bind the Media Player Entry URL to Service Access Information | TS 126 512 | **addressed**, differently |
| 4 | No mechanism for implicitly launching the Media Session Handler | TS 126 512 | **not a gap**, the report says so itself |
| 5 | No notification that QoE metrics reporting was activated | TS 126 512 | **closed**, relocated |
| 6 | Playback state not explicitly exposed in M7 status | TS 126 512 | **closed** |
| 7 | No notification that a metrics report was submitted | TS 126 512 | **closed**, relocated |
| 8 | `OPERATION_POINT_CHANGED` carries no payload; no operation point in status; no external reference | TS 126 512 | **closed** |
| 9 | No client API to request network assistance | TS 126 512 | **closed**, relocated |

**The client APIs moved.** In TS 126 512 V18.6.0 the clauses the report cites for gaps 5, 7 and 9,
namely 12.2.5, 12.2.6 and 12.2.7, are all marked Void, and that material now lives in TS 26.510
(published by ETSI as TS 126 510), which 126 512 references throughout. The report's clause numbers
for those gaps no longer locate anything: the status has to be read in the newer document.

**Gaps 5 and 7 are closed** in TS 126 510 V19.1.0 clause 11.6.2. Table 11.6.2-2 lists
`METRICS_REPORTING_ACTIVATED` and `NEW_METRICS_REPORT` among the notification events the Media
Session Handler exposes, which are the activation and submission announcements the report asked
for, and table 11.6.2-1 adds `lastMetricsReport` status information alongside them.

**Gap 9 is closed** by clause 11.4 of the same document, a Network Assistance client API with its
own methods and status information, where the report found an empty clause.

**Gap 6 is closed.** TS 126 512 V18.6.0 table 13.2.6-1 now carries a `state` row holding an
enumerated value from table 13.2.2-1 indicating the current state of the Media Player, which is
precisely what the report proposed instead of inferring it from a non-zero playback rate.

**Gap 8 is closed, both halves.** `OPERATION_POINT_CHANGED` now declares a payload of the media
delivery session identifier together with the external reference identifier of the currently
selected Service Operation Point, and the dynamic status information exposes
`serviceOperationPoints` with an indication of which is current. The external reference the report
wanted, for correlating an operation point with a Representation in the MPD, is the mechanism
`externalReference` now provides.

**Gap 3 is addressed, though not in the way proposed.** The report suggested an additional M7
method. Instead, `attachMPD()` in TS 126 512 V18.6.0 clause 13.2.3.3 takes a media delivery session
identifier alongside the MPD URL, so the presentation is bound to an already-initialised session
rather than to the access information directly. Whether that satisfies the intent is a judgement
call rather than a matching of text, and it should be confirmed with 3GPP before being relied on.

### What this leaves

Of fourteen items, six are closed, one is addressed by restructuring, one the report itself says
needs no specification work, three are open, and three were not checked.

**Every open item is on the DVB side**, and they are the same shape: the service list has nowhere to
put a 5G locator, whether for 5G Broadcast (gap 5) or for 5GMS access information (gaps 1 and 2).
The 3GPP side of this integration has largely moved on; the DVB side has not, and its draft
successor does not either.

That is a useful thing to know before planning work: the missing piece is a service list extension,
which is small, well understood, and squarely in DVB's court.

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
