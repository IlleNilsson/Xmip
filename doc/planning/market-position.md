# Where Xmip stands

## The position

Stated by the owner, 2026-08-30. Everything below this section is evidence;
this is the claim the evidence serves.

**Xmip is the replacement for BizTalk, MuleSoft and their kind. On-premises
first, cloud-installable.**

Each word carries weight. *Replacement*, not migration target: the vocabulary
is deliberately BizTalk's — Receive Locations, Send Ports, promoted properties
— so twenty years of operator knowledge transfers rather than expires, minus
the parts BizTalk got wrong, each recorded in a decision with its reason.
*On-premises first*: the deployment model's primary shapes are the single
server and the on-prem cluster, because the estates Xmip is for cannot move —
law, latency, air gaps, other people's data. *Cloud-installable*, not cloud
native and not cloud hosted: a cloud node is one more place a node runs
(`deployment-model.md`), never a dependency, and nothing in Xmip phones
anywhere to work. Section 2 below is why this position is open at all:
Microsoft's path is to the cloud only, and every competitor sentence in
section 4 leads with a hosted service.

Surveyed 2026-08-27. Every date below is published and checkable; every
judgment is marked as one. Re-check the dates rather than trusting this
document once they start passing.

## 1. The runway is public, and one deadline is next month

| Date | What happens |
| --- | --- |
| 2026-09-30 | BizTalk 2020's default Service Bus adapter stops working. It uses SBMP, which is retired. Every BizTalk-to-Azure integration built on it fails. |
| 2027-01-11 | BizTalk Server 2016 leaves extended support. |
| 2028-04-11 | BizTalk Server 2020 leaves mainstream support. |
| 2030-04-09 | BizTalk Server 2020 leaves extended support. |

Microsoft confirmed on 2026-01-09 that **BizTalk Server 2020 is the final
version**. There will not be another.

The September date is the one that matters commercially, because it is the
first that forces a decision rather than merely warning of one.

## 2. Microsoft's migration path is to the cloud, and only to the cloud

All new investment goes to Azure Integration Services and Logic Apps. There is
no first-party on-premises successor and none is planned.

**That is the hole Xmip stands in.** An estate that cannot move to a hyperscaler
— for law, for latency, for an air gap, or because the data is somebody else's —
has no first-party option at all.

## 3. Sovereignty is the tailwind, and it is larger than it looks

- Sovereign cloud spending reaches **$80B globally in 2026**; Europe alone
  **€12.6B**, up **83% year on year**.
- **82%** of German companies say they want independence from US providers.
  **78%** remain dependent. Trust in US providers sits at **38%**.
- Several German states have mandated migration away from Microsoft 365 in
  government offices. France's *Cloud de Confiance* requires public-sector cloud
  to be operated by European entities under European law.
- The stated concern is the US CLOUD Act reaching data that is physically
  resident in the EU.

A Swedish, on-premises-capable, source-available integration platform is aligned
with a market condition that did not exist five years ago. **This is the single
strongest thing Xmip has going for it and it is not a technical property.**

Honest counterweight, from the same sources: no European enterprise will leave
the US hyperscalers entirely in 2026. The gap between wanting independence and
having it is the whole market.

## 4. The closest competitor has already written our sentence

**CData Arc** markets itself as *the on-premises-first EDI and MFT platform that
replaces BizTalk without forcing a cloud migration*. Proprietary, visual-designer
led, EDI and MFT focused, shipping quarterly.

That is Xmip's positioning, taken, by an incumbent with a product. Worth studying
properly rather than dismissing — specifically, what they do **not** cover.

The broader field — MuleSoft, Boomi, IBM webMethods, SAP Integration Suite,
Workato — is iPaaS and sells the cloud. iPaaS is $9.24B in 2026 heading to
$20.93B by 2031. None of them competes for the estate that will not move.

## 5. Healthcare's default open-source engine went commercial

NextGen announced on 2025-03-19 that **Mirth Connect 4.6 and later are
commercial-only**. 4.5.2 is the last open-source release and receives no further
security patches.

Two community forks now exist: **BridgeLink** (sponsored by Innovar Healthcare)
and the **Open Integration Engine**, under a non-profit steering committee.
Neither is an incumbent.

Healthcare interoperability was $4.8B in 2025 and is projected past $7.5B by
2028. Xmip already covers HL7 v2 and FHIR.

## 6. AS4 stopped being optional

| Date | Mandate |
| --- | --- |
| 2026-01-01 | Belgium: all B2B via Peppol. **Live now.** |
| 2026-09 | France: every business must be able to *receive* e-invoices. |
| 2027-01-01 | Germany: companies over €800k turnover. |
| 2028-01-01 | Germany: all companies. Belgium adds continuous transaction reporting, likely 5-corner. |
| 2030 | ViDA: EN 16931 structured invoices and near-real-time cross-border B2B reporting. |

Peppol runs on **AS4**. `xmip-core-authenticate/doc/identity-by-technology.md`
added `xmip-core-transport-as2` and `xmip-core-transport-as4` to the manifest and
recorded them as absent. That was the right call before there was a timetable;
there is now a legislated one.

## 7. Nobody is building an integration platform in Rust

Real Rust messaging infrastructure exists — Danube, RingLog, Rafka, Broccoli —
but every one is a broker or a queue. No Rust ESB or integration engine was
found.

Both halves of that matter. It is differentiation nobody can claim, and it means
there is no ecosystem to borrow adapters, mappers or EDI parsers from. Every one
of them is ours to write, in a language with no incumbent library for any of it.

## 8. Re-checked 2026-09-23: what changed, and what Xmip needs

The owner asked what Xmip needs against the competition. Sections 1-7 were
re-checked against their sources and newer ones; they stand as written on
2026-08-27, and where they no longer hold, it is said here rather than in
place, so the survey and its correction can both be read.

**What no longer holds.**

- **Section 1.** Microsoft shipped a hotfix (KB5091379) adding AMQP to the
  SB-Messaging adapter, so SBMP's retirement on 2026-09-30 forces a hotfix,
  not a platform decision. Microsoft's own lifecycle post announcing 2020 as
  the final version is from December 2025; 2026-01-09 is a third party's.
  Paid extended support runs 2028-2030.
- **Section 2.** The Logic Apps hybrid deployment model reached general
  availability in June 2025 and runs on customer infrastructure. It is not
  disconnected: it needs Azure Arc-enabled Kubernetes, outbound connectivity
  to Azure and SQL, and its managed connectors run in Azure. The hole is
  **no first-party disconnected successor**, not no on-premises one.
- **Section 4.** "None of them competes for the estate that will not move"
  is wrong. MuleSoft's private-cloud edition targets air-gapped sites; IBM App
  Connect Enterprise and webMethods self-host; Seeburger, Axway B2Bi and Cleo
  run on-premises with conformant AS4; Kestra 2.0 (Apache 2.0, 2026-09-08)
  sells air-gapped orchestration. CData Arc now adds Git versioning, an MCP
  server, encryption at rest and hash-chained, tamper-evident logs, and runs
  on Linux and macOS through its Java edition.
- **Section 5.** The Open Integration Engine shipped 4.6.0 on 2026-07-09 and
  applied to the Eclipse Foundation. And "Xmip already covers HL7 v2 and
  FHIR" overclaims: the technologies exist, no node runs them.
- **Section 6.** France requires receiving through a DGFiP-registered
  platform, which a Peppol access point alone is not; Germany has required
  every business to receive since 2025-01-01, and e-mail counts; ViDA was
  adopted 2025-03-11 with intra-EU duties from 2030-07-01; OpenPeppol makes
  ISO 27001 mandatory for service providers from 2027-07-01. AS4 is
  mandatory for access-point operators, not for every business, so Xmip
  ships AS4 and Peppol as protocol software a certified operator runs.
- **Section 7.** Still narrowly true, but Apache Iggy (incubating) now has a
  Rust connector runtime that loads plugins dynamically, the pattern of
  ADR-0057.
- **"The largest product gap is not in the runtime"**, below, is stale:
  the GUI and PowerShell repositories are built. The largest gap is now the
  runtime itself — no node can run a technology (open-problems.md, Suggested
  order) — and then transformation.

**Table stakes Xmip lacks**, in the order open-problems.md's Suggested order
takes them (judgment, with the survey behind it):

1. A node that runs: phases 4-9, a technology in a node, a real Receive
   Location. Every row below depends on it.
2. Transformation. BizTalk estates are thousands of XSLT 1.0 maps; CData sells
   reusing them and Microsoft ships a map converter. All seventeen `transform`
   technologies are reserved.
3. Durable state across restart, deduplication, and Journey replay.
4. Tracking and message search: find a Message by promoted property, see its
   body, resubmit it. Every audit, report and observe sink is reserved.
5. EDI completeness: interchange control numbers, acknowledgements (997, 999,
   TA1, CONTRL), batching, agreement-driven validation — trading-partner
   agreements in `party`.
6. Secrets and keys: a local encrypted store, the platform key stores, PKCS#11
   and a vault. Nothing in the manifest holds a secret. **Needs a home.**
7. Sign, encrypt, compress: all twenty `prepare` technologies are reserved,
   and AS2 and AS4 need S/MIME, WS-Security and compression.
8. One orchestration technology with correlation, timeouts and compensation.
9. Polling schedules for a Receive Location (SFTP, FTP, SQL, calendar).
10. High availability and placement.
11. An OpenTelemetry exporter.
12. A signed release with an SBOM and a vulnerability policy: the Cyber
    Resilience Act's reporting duties for manufacturers began 2026-09-11.
13. BizTalk artifact import — bindings, schemas including flat-file
    annotations, maps. The highest-leverage item outside the runtime, and
    **needs a home**.

**Worth keeping, because nobody else has them:** running disconnected with no
control plane; refusals that carry place and reason; `never_satisfiable`;
identity isolation that fails closed at startup; the breadth of industrial
transports (OPC UA, IEC 61850, Modbus, PROFINET, M-Bus), which no iPaaS here
covers. Tamper-evident audit is no longer unique, so it must be matched, not
claimed.

**Deliberately not:** a hosted control plane; metering or telemetry that phones
home; a catalogue of SaaS connectors (generic HTTP and OpenAPI, and the ABI
for third parties, instead); an API-management product; a language model in
the message path — an MCP server over the read-only operator boundary is the
credible step; being a certified Peppol access point, which is an
organization's certification, not software.

Sources for this section are listed under **Sources, 2026-09-23** at the end.

## What this forces

### The license costs adoption, knowingly

Enterprise legal teams reject AGPL as policy. That is the consistent finding, and
it is a real cost that ADR-0023 accepts on purpose: dual licensing would remove
the objection, and the right that makes dual licensing possible is the same right
that makes relicensing possible. Mirth Connect is the worked example of what that
right gets used for.

Settled. Not open.

### The largest product gap is not in the runtime

Every competitor leads with a visual designer. Boomi, MuleSoft, CData Arc, Mirth,
Rhapsody — without exception.

`xmip-core-gui` and `xmip-core-powershell` are empty repositories. ADR-0014
declares them .NET 11 and `xmip-template-dotnet` now exists, so the obstacle is
work rather than a decision.

**Judgment, not fact:** this gap is wider than any runtime feature currently
open, including ToDo.

## What to say out loud

Three properties were searched for in the market and not found:

**Identity-context isolation, enforced at startup, failing closed.** ADR-0022. In
BizTalk, separating receive, process and send into different hosts is convention
applied by an administrator who knows to do it — nothing enforces it and nothing
reports when it has not been done. Xmip refuses to start.

**Declines that explain themselves.** `xmip-core-route` records why every
Subscription passed on a Message. In BizTalk that answer lives in MessageBox rows
needing a separate tool to read.

**`never_satisfiable`.** A filter naming a property no deployed Contract can
promote is found before deployment, with no traffic. In BizTalk the Subscription
is accepted, never matches, and the first symptom is a Message going nowhere
months later. **No product was found that does this.**

## Sources

- BizTalk end of life and Azure succession —
  <https://www.schneider.im/microsoft-azure-logic-apps-will-replace-biztalk-server-2020/>,
  <https://www.transparency.com/app-innovation/the-biztalk-lifecycle-biztalk-server-versions-end-of-life/>
- SBMP retirement and migration timeline —
  <https://www.sixpivot.com.au/post/biztalk-server-end-of-life-critical-timeline-and-migration-strategy-for-enterprise-integration>
- CData Arc positioning — <https://arc.cdata.com/lp/biztalk-eol/>
- European sovereignty —
  <https://massivegrid.com/blog/european-companies-leaving-us-cloud/>,
  <https://blog.elest.io/digital-sovereignty-in-2026-how-eu-data-residency-laws-are-driving-the-self-hosting-boom/>
- Mirth Connect licensing —
  <https://www.nextgen.com/blog/industry-news/a-new-era-for-mirth-connect-by-nextgen-healthcare>,
  <https://nirmitee.io/blog/mirth-connect-alternatives-2026-after-licensing-change/>
- Healthcare engines and market size —
  <https://mirth.support/best-hl7-integration-engines-2026>
- Peppol and ViDA —
  <https://www.fonoa.com/resources/blog/peppol-adoption-europe-2026-mandates-vida>,
  <https://peppolvalidator.com/peppol-mandates>
- Rust messaging — <https://github.com/topics/message-broker?l=rust>
- AGPL in commercial open source —
  <https://ossalt.com/guides/oss-licensing-guide-mit-apache-agpl-2026>
- iPaaS market —
  <https://www.g2.com/products/ibm-webmethods-hybrid-integration-2025-12-05/competitors/alternatives>

## Sources, 2026-09-23

- Microsoft lifecycle post — <https://techcommunity.microsoft.com/blog/integrationsonazureblog/microsoft-biztalk-server-product-lifecycle-update/4478559>
- SBMP retirement and the AMQP hotfix — <https://techcommunity.microsoft.com/blog/integrationsonazureblog/service-bus-sbmp-retirement-what-biztalk-server-2020-customers-need-to-know/4513155>
- Logic Apps hybrid GA and its requirements —
  <https://techcommunity.microsoft.com/blog/integrationsonazureblog/announcement-general-availability-of-logic-apps-hybrid-deployment-model/4422414>,
  <https://learn.microsoft.com/en-us/azure/logic-apps/set-up-standard-workflows-hybrid-deployment-requirements>
- BizTalk orchestration migration tool — <https://techcommunity.microsoft.com/blog/integrationsonazureblog/a-biztalk-migration-tool-from-orchestrations-to-logic-apps-workflows/4494876>
- CData Arc — <https://arc.cdata.com/blog/cdata-arc-release-q1-2026>,
  <https://community.cdata.com/cdata-arc-48/introducing-the-arc-q2-2026-release-1827>
- MuleSoft private-cloud edition — <https://blogs.mulesoft.com/dev-guides/private-agentic-ai-with-mcp-and-a2a-support-in-mulesoft-pce/>
- EU eDelivery AS4 conformant solutions — <https://ec.europa.eu/digital-building-blocks/wikis/display/DIGITAL/eDelivery+AS4+conformant+solutions>
- Kestra 2.0 — <https://kestra.io/blogs/kestra-2-0-what-you-actually-get>
- Open Integration Engine — <https://github.com/OpenIntegrationEngine/engine/releases>
- France — <https://www.avalara.com/blog/en/europe/2026/08/peppol-vs-pfdp-france-e-invoicing.html>
- ViDA — <https://www.nortonrosefulbright.com/en/knowledge/publications/7f7569e5/vat-in-the-digital-age-vida-package-finally-adopted>
- Peppol ISO 27001 — <https://www.vatupdate.com/2026/07/13/iso-27001-is-now-mandatory-for-all-peppol-service-providers/>
- Cyber Resilience Act reporting — <https://digital-strategy.ec.europa.eu/en/policies/cra-reporting>
- Apache Iggy connectors — <https://iggy.apache.org/blogs/2025/06/06/connectors-runtime/>
