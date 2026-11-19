# ADR-0040: Xmip retains and archives; it does not delete

- Status: Accepted
- Date: 2026-09-06
- Related: ADR-0013 (the Journey model), ADR-0028 (the Xmip Essentials),
  doc/architecture/observability-model.md, `xmip-core-retain`

## In brief

- Theme: What Xmip is at runtime
- Subject: Retention ends at archiving; deleting data is not Xmip's responsibility
- Name: Xmip retains and archives, it does not delete
- Order: 11
- Concepts: Retention; archiving; the archive owner; no deletion

**Xmip gets data, transforms it, waits for business decisions, and sends one or
more outputs. For the data it holds, it does exactly two things over time: it
**retains** it while it is live, and **archives** it when its retention window
passes. It never deletes. Once archived, what becomes of the archive is the
archive owner's decision, not Xmip's.**

## Context

The owner, 2026-09-06, watching the Essentials' secretary scenario, which had
grown a third stage called *purge*: *First keep retention, then archive. If all
fails, archive. Do not delete — that is not Xmip's responsibility. Xmip gets
data, transforms, waits for business decisions, sends one or multiple data. Xmip
does not delete; retention and archiving. Then the user of the archive decides
what to do about the archive.*

The word *purge* was the assistant's, introduced without the owner's say-so and
absent from terminology.md. Worse than the word, it implied an action Xmip does
not take. The estate's own `xmip-core-retain` crate carried a `RetentionAction::
Delete`, so the drift was in the code, not only the label.

## Decision

### 1. Two retention actions, not three

`RetentionAction` is `Keep` and `Archive`. `Delete` is removed. Retention keeps
data live while it is young and archives it once it passes its window; there is
no third action, because deleting is not a thing Xmip does.

### 2. Archiving is terminal for Xmip

Archiving is the last thing Xmip does with a piece of data it is holding. The
archive is a handoff: once an item is in the archive store, Xmip's
responsibility for it is discharged. It does not later revisit the archive to
remove anything.

### 2a. Archiving is a configured ability, not a command

Archiving is *configured*, never commanded. A node or process declares it — which
archive store, which format (`parquet`, `aws-s3`, `sql`, …), and the retention
windows — in its configuration, and the runtime enacts that declaration by age.
There is no operator or runtime command to "archive"; it is an ability set under
Configure (an Operator's surface, ADR-0009), like retention itself, not an action
like pause. The `archive` capability and its format technologies are what a
configuration selects among.

### 3. Deletion belongs to the archive owner

Whether, when and how archived data is deleted is decided by whoever owns the
archive — a records office, a compliance regime, a downstream system — not by
Xmip. Xmip provides the archive; the owner disposes of it. This keeps the
platform clear of a responsibility (destroying a Party's records) that is
theirs to hold and theirs to answer for.

### 4. The scenario matches

The Essentials' Retention test — the secretary scenario until 2026-09-19, when
the owner replaced the old scenario wording with the test names everywhere — is
two stages, **retain**, then **archive** (ADR-0028).
Archived items accumulate; the scenario never purges them, because Xmip never
does. A missed sweep under pressure still surfaces as a retention or archive
leak, which is the property the scenario exists to prove.

## Consequences

- `xmip-core-retain`'s `RetentionAction` loses `Delete`; only the essentials
  consumed it, so the change is contained.
- The secretary scenario drops its `purge` stage and its "delete by age" path.
- terminology.md's retention vocabulary stays *retention* and *archiving*; no
  *purge*, no *delete*, is introduced.
- A reviewer treats any future "Xmip deletes data" path as a defect against this
  record, whatever it is called.
- If a deployment needs archived data destroyed on a schedule, that is the
  archive owner's mechanism to build against the archive Xmip produced, and a
  separate decision if it ever touches Xmip at all.

## Provenance

The ruling is the owner's, 2026-09-06: *Xmip does not delete; retention and
archiving; then the user of the archive decides.* The two-action framing, the
archive-as-handoff wording and the crate/scenario consequences are the
assistant's drafting of it, on the instruction to write it down, having first
introduced the *purge* the owner corrected.

## Amendment, 2026-11-13: the cluster's membership is kept, never deleted

**Provenance.** The design the owner approved on 2026-11-12, section 3.2:
*Rows are kept, never deleted (ADR-0040)*; its fourth landing piece is
membership through Xmip Storage (ADR-0056 and ADR-0058, amendments of the
same day).

The administration database's `membership` table holds a row for each
start of each node: written once the node reaches Xmip Storage, and again,
saying when, as it stops in order. A node started again writes a row of its
own, keyed by the process it runs in, which is drawn new at each start; its
row before stays, and only stops being its node's latest. Nothing in Xmip
removes a row: `XmipStorage` has no operation that could. The members now
are each node's latest row, found by one range of an index that holds only
those (`membership_latest`), so the history kept costs a read nothing; the
timing program holds a row's write within a millisecond beyond Xmip
Storage's own write over a thousand starts of each node kept
(`xmip-core-persist`, `tests/measured/membership.rs`). A node that left the
cluster stays a member, its row saying it stopped in order or, where it was
killed, saying nothing, until its environment says it left (the design's
section 9; not built: nothing says a node left yet); what becomes of the
history beyond that is the archive's, as clause 3 says.

## Amendment, 2026-11-19: an archived item is never written over

**Provenance.** An outside review, confirmed against the source by the
coordinator on 2026-11-19: the archives wrote over what they held, and an
overwrite deletes what was there — by the Consequences above, a defect
against this record. The design is the planner's and the coordinator's,
decided while designing and told to the owner the same day: the file
archive's copies retired, the object stores' metadata the TOML sidecar, a
data type beginning with a dot refused.

What was found. The object archives (aws-s3, azure-blob,
google-cloud-storage) put an item's bytes and then its metadata, each by a
plain put: an identifier archived again replaced both, so the first
receipt restored the second's bytes or failed its checksum, and the
metadata at `<key>.meta` was the name of another item, so `order.meta`
archived after `order` replaced `order`'s metadata. The Parquet archive
made its file with `File::create`, which empties one already there. The
file archive wrote the bytes at their own name, unsynced, then the
sidecar: a failure between the two left bytes without metadata, a crash
part of a file; and it kept an identifier archived again beside the first
as `<identifier>.2`, `.3`, a rule only its README and commit 826d017
recorded.

What stands now:

1. **An item is two objects under one prefix: its bytes at
   `<prefix>/<data_type>/<identifier>`, its metadata at
   `<prefix>/.meta/<data_type>/<identifier>`** (`archive::layout`), so no
   item's name is another's metadata. The metadata is the TOML sidecar
   for every archive keyed by name, with the SHA-256 of the bytes
   (`archive::sidecar`; ADR-0044, amendment of the same day). A data type
   beginning with `.` is refused; the data type's `/` becomes `_`; two
   items laid out at one name — `text/plain` and `text_plain`, or in a
   directory two identifiers made the same file name — are refused in
   words.
2. **The metadata is created first, as the claim; the bytes next; the
   receipt only after both** (`archive::named`, once for every archive
   keyed by name). A store creates an object only where none is and never
   replaces one: an object store by its conditional put, a file system by
   a file written beside its name, synced, hard-linked to the name — which
   is refused where the name is taken — and its directory synced
   (`archive::whole`, `file::synced::directory`). Where the metadata is
   there already, the same item — data type, identifier and checksum —
   carries on, so an archive stopped between the two is completed by its
   repeat; another item is refused, and nothing is written. Where the
   bytes are there already, their SHA-256 must be the item's; other bytes
   are left as they are and the item is refused.
3. **A restore reads the metadata first.** Where there is none, the
   location is not an item this archive completed, and it is refused; the
   receipt's checksum, the metadata's and that of the bytes read must
   agree.
4. **The Parquet archive's file is made the same way** (`archive::whole`);
   where one is there, the same item answers the same receipt and any
   other is refused (`archive::named::Claim`).
5. The `.meta`-suffix layout and the file archive's numbered copies are
   deleted, not migrated.

What it costs: an archive's happy path is the same two writes and a
restore the same two reads; a repeat adds a read of what is there; on a
file system each object adds a sync of its directory. Archiving is off the
message path.

Shown by the file archive's tests, written first and run against the code
before this change on 2026-11-19 on Windows (`cargo test -j 2 --config
.local-work/landing/patch.toml -- --test-threads 2` in
`module/core/operation/archive/file`):

```text
test tests::a_data_type_beginning_with_a_dot_is_refused ... FAILED
test tests::a_foreign_object_at_the_key_is_refused ... FAILED
test tests::an_archived_item_is_a_file_with_its_metadata_beside_it ... FAILED
test tests::an_identifier_archived_again_with_other_bytes_is_refused_and_the_earlier_receipt_restores ... FAILED
test tests::an_interrupted_pair_is_completed_by_its_repeat_and_refuses_another_item ... FAILED
test tests::bytes_without_metadata_are_refused_on_restore ... FAILED
test tests::an_identifier_archived_again_with_the_same_bytes_answers_the_same_receipt ... FAILED
test tests::two_identifiers_that_sanitize_alike_are_refused ... FAILED
test result: FAILED. 11 passed; 8 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.90s
```

`order_and_order_meta_are_two_items` passed there already: a file name
holds no dot. The Parquet archive's, the same way in
`module/core/operation/archive/parquet`:

```text
test tests::an_identifier_archived_again_with_other_bytes_is_refused_and_the_earlier_receipt_restores ... FAILED
thread 'tests::an_identifier_archived_again_with_other_bytes_is_refused_and_the_earlier_receipt_restores' (13580) panicked at src\lib.rs:229:14:
test result: FAILED. 4 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.13s
```

`an_identifier_archived_again_with_the_same_bytes_answers_the_same_receipt`
passed there: `File::create` wrote the same bytes over themselves. The file
archive's `a_write_failing_half_way_leaves_no_item` came after that run; it
fails a write through `archive::whole`, which the code before had no seam
for (its `write_new` removed a failed file, unsynced). After the change, the
same command in each crate on Windows, with `cargo clippy --all-targets
--all-features -- -D warnings` and `cargo fmt --check` clean in each:

```text
module/core/operation/archive          test result: ok. 33 passed; 0 failed
module/core/operation/archive/file     test result: ok. 14 passed; 0 failed
module/core/operation/archive/parquet  test result: ok. 5 passed; 0 failed
module/foundation/core                 test result: ok. 73 passed; 0 failed
module/core/capability/transport/file  test result: ok. 34 passed; 0 failed
```

And in the AlmaLinux 10 guest, clippy as above clean:

```text
module/core/operation/archive          test result: ok. 33 passed; 0 failed
module/core/operation/archive/file     test result: ok. 14 passed; 0 failed
module/core/operation/archive/parquet  test result: ok. 5 passed; 0 failed
module/foundation/core                 test result: ok. 72 passed; 0 failed
module/core/capability/transport/file  test result: ok. 32 passed; 0 failed
```
