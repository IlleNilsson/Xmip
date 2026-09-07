# ADR-0023: AGPL-3.0-or-later, and no second licence

- Status: Accepted
- Date: 2026-08-27
- Related: ADR-0012 (the module boundary)

## In brief

- Theme: How the work is done
- Subject: AGPL-3.0-or-later, and no second licence
- Name: AGPL-3.0-or-later
- Order: 3
- Concepts: Licence, AGPL, dual licensing, CLA

One licence, and no commercial one. A platform that cannot be relicensed cannot
be closed, and holding the right to grant a second licence is the same right
that makes closing it possible. Mirth Connect went commercial-only in March
2025; Xmip gives up the ability to do that.

No contributor licence agreement is needed, because there is no second licence
to grant. Some buyers will refuse Xmip on licence grounds alone, knowingly.

## Context

Every Xmip repository is AGPL-3.0-or-later. That was settled early and has never
been in question. What did not exist was a record of it — ADR-0012 clause 9
answers whether the *module boundary* carries a licence exception, not why Xmip
is licensed the way it is.

The absence invited the question to be reopened, on 2026-08-27, by someone
reading the estate and finding no record. This exists so it is not reopened
again.

## Decision

**Xmip is AGPL-3.0-or-later. There is no commercial licence and no dual
licensing.**

## Why

**A platform that cannot be relicensed cannot be closed.** This is the whole of
it. On 2025-03-19 NextGen moved Mirth Connect to a single commercial licence at
4.6; 4.5.2 was the last open-source release and receives no security patches.
Two community forks now exist because the guarantee was not there. The estate
Xmip is built for — regulated, sovereign, air-gapped, running somebody else's
data on a ten-year horizon — has just watched that happen and has reason to care.

Dual licensing is the mechanism that makes it possible. Holding a second licence
means holding the right to grant one, which means owning every contribution,
which means the door to closing the product is never actually shut. Not holding
that right shuts it permanently, and being unable to change course later is the
point rather than a cost.

**Nothing is owed to anyone's procurement policy.** Enterprise legal teams reject
AGPL as policy. That is a real cost and it is accepted knowingly. A user takes
Xmip under Xmip's licence and may additionally have to satisfy the licences of
what Xmip itself depends on; reconciling that is the user's business, not
Xmip's. ADR-0012 clause 9 said this about the boundary and it is equally true of
the product.

## Consequences

- **No contributor licence agreement is needed.** A CLA exists to let a project
  grant a licence it could not otherwise grant. With one licence there is
  nothing to grant, and contributors keep their copyright under the AGPL like
  everyone else. This removes permanent administrative cost and one deterrent to
  casual contribution.
- **Some buyers will refuse Xmip on licence grounds alone.** Accepted.
- **The boundary is unaffected.** `include/xmip_module.h` stays
  AGPL-3.0-or-later. A third party writing a Module compiles against a C ABI
  rather than against Xmip source, which is a technical boundary and was never a
  licence exemption. ADR-0012 clause 9, unchanged.

## What was considered and rejected

**AGPL plus a commercial licence**, as Grafana, Mattermost, Bitwarden and
Nextcloud ship. It funds the work and it removes the procurement objection.
Rejected because the right that makes it possible is the same right that makes
relicensing possible, and giving that right up is the guarantee Xmip is offering.
