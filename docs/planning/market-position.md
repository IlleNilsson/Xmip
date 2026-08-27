# Where Xmip stands

Surveyed 2026-08-27. Every date below is published and checkable; every
judgement is marked as one. Re-check the dates rather than trusting this
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

Peppol runs on **AS4**. `xmip-core-authenticate/docs/identity-by-technology.md`
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

## What this forces

### The licence costs adoption, knowingly

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

**Judgement, not fact:** this gap is wider than any runtime feature currently
open, including XmipToDo.

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
  <https://www.transparity.com/app-innovation/the-biztalk-lifecycle-biztalk-server-versions-end-of-life/>
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
