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

## Amendment, 2026-11-20: a file left under its mark is removed, and the Parquet receipt is the file archive's

**Provenance.** Open problems 76 and 78, both found with the amendment of
2026-11-19 and taken up by the coordinator on 2026-11-20. The design is
the assistant's, decided while designing and for the owner to overrule:
the operating system, not a name, says which file is left.

What was found. An archive on a file system writes a file beside its name
as `<name>.xmip-archiving.<process>.<count>` and links it to its name
(`archive::whole`). A process that died between the two left that file,
and nothing removed it: not the archive, which has no start of its own,
and not the file transport's sweep, which removes only the sent files its
own node named (ADR-0024, amendment 2026-10-19). A process given a dead
one's id again found its first such name taken, and its first write
failed. And the Parquet archive's receipt was the file's path as the
platform prints it, with no checksum: its restore opened whatever path a
receipt named and gave back whatever bytes the file held.

What stands now:

1. **A file is held by the process writing it, from the moment it is made
   until it is closed** (`file::held::create`, in `xmip-core-library-file`):
   on Unix by an exclusive lock on it (`flock`), on Windows by the sharing
   it is opened with, which lets another handle read it and never write,
   rename or remove it. `whole` keeps it held through its link to the
   name. A Unix removal can come only between the file's making and its
   lock; the writer then finds its name gone and makes it again. Windows
   takes no lock on it: a lock there is mandatory, and would refuse a
   reader of the name the file is linked to, as a read of a file the
   standard library's `File::lock` held was refused on 2026-11-20
   (`ERROR_LOCK_VIOLATION`, os error 33).
2. **A process's first write into a directory starts a sweep of it, which
   removes every file there under the mark that no process holds**
   (`whole`'s sweep, through `file::held::remove_unheld`): unlinked, or a
   second name of a file linked. That is how a file is known to be left:
   the operating system has closed everything a dead process held, and
   holds what a live one is writing, in this process or another, which is
   never removed. No process id, name or age is read to decide it. An
   archive's start in a directory is its first write there, as a Send
   Location's is its node's start. **The sweep runs beside the write**, on
   a thread of its own (`xmip-archive-sweep`, one for each directory a
   process writes in, started the estate's way, by the standard library's
   `thread::Builder`): a directory holds a file for each item archived,
   and the write waits for no listing of them. It is safe beside every
   write, because a held file is never removed, and on Unix a writer whose
   file a sweep took before its lock makes it again. Where no thread can
   be started, the directory is swept from the process's next write there.
   What cannot be listed or removed is left under its mark for the next
   process's first write; no write needs any of it. A test waits for a
   sweep through `whole::swept`, under `test-support`.
3. **The Parquet archive's receipt is the file archive's**:
   `file:///<root>/<data_type>/<identifier>.parquet` and the SHA-256 of
   the bytes. Both come from `archive::directory::Directory`, moved there
   from the file archive, which reads a receipt's key back only under its
   root and only where every segment names a file there: a segment that is
   empty, `.`, `..`, or holds a `\` or a `:`, which Windows reads as a
   separator or a drive, is refused (the last two found while moving it).
   A restore refuses bytes whose SHA-256 is not the receipt's, nor the
   metadata's where a store keeps one, through `archive::checksum::verify`,
   once for the name-keyed stores, the Parquet archive and the SQL script
   archive, whose own comparisons are deleted.
4. The file transport's sweep stays as it is. Its rule is the owner's of
   2026-10-19 — a node removes the sent files its own name left, never
   another node's — over any far end of the file family (`ClaimSite`), and
   it shares no code with a local file held by its process.
5. **What the file system does for a write is its time, not Xmip's.**
   `whole` runs the file's making, its link, its close and the removal of
   its written name each as an I/O (`xcore::spent::on_io`), as its syncs
   are the disk's (`on_sync`); the bytes a caller writes into the file stay
   the caller's to account. Until then the four were counted as Xmip's own
   share of each write: about two milliseconds on Windows, where the
   system charges what its file system filters do to the calling thread.

What it costs: a process's first write into a directory starts a thread;
the thread lists the directory once, beside the writes, in time with the
names it holds; on Unix each write takes a lock and reads the file's
identity once; on Windows nothing more. On Windows the writes that overlap
the listing of their own directory wait on it by the clock — NTFS lists
and adds to one directory in turn — though not by their own share.

Shown by the tests, written first and run against the code before this
change on 2026-11-20 on Windows (`cargo test -j 4 --config
.local-work/landing/patch.toml --all-features -- --test-threads 4` in each
crate):

```text
module/core/operation/archive
test whole::tests::a_file_left_under_its_mark_is_removed_by_the_next_create_in_its_directory ... FAILED
test result: FAILED. 33 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.04s
module/core/operation/archive/file
test tests::a_file_left_under_its_mark_is_removed_by_the_next_archive_into_its_directory ... FAILED
test result: FAILED. 14 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.15s
module/core/operation/archive/parquet
test tests::a_receipt_from_under_another_root_is_refused ... FAILED
test tests::a_file_left_under_its_mark_is_removed_by_the_next_archive_into_its_directory ... FAILED
test tests::the_receipt_is_a_file_uri_under_the_root_with_the_sha256_of_the_bytes ... FAILED
test tests::bytes_changed_since_they_were_archived_are_refused_on_restore ... FAILED
test result: FAILED. 5 passed; 4 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.09s
```

`bytes_changed_since_they_were_archived_are_refused_on_restore` failed at
its `expect_err`: the restore gave the other bytes back. The tests of a
file a live write holds — `file::held`'s three, `whole`'s
`a_file_a_live_write_holds_under_its_mark_is_never_removed`, the file
archive's `a_file_another_archive_is_writing_is_never_removed` — call
`file::held`, and the new tests of `directory` and `checksum` call
`Directory` and `verify`: none of the three was there before. `held`'s
`a_removal_in_the_instant_after_the_file_is_made_never_takes_it_from_its_writer`
removes the file between its making and its hold: on Unix the removal
succeeds and the writer makes the file again, on Windows it is refused.
The first sweep listed its directory inline, before the write it ran in.
`the_first_write_into_a_full_directory_waits_for_no_sweep` holds that it
does not: in a test's folder of 50,000 empty items, synced once, the first
write's own share — the processor time it took outside its syncs and its
file system calls (`xcore::spent`) — must be within a millisecond of the
slowest of the twenty writes after it. It holds a time, so it is the
archive module's timing program, `measured` (`tests/measured/main.rs`,
`test = false`, `required-features = ["test-support"]`; rust-style.md
section 5c), run alone after every other test; what a sweep removes is
held apart by `whole`'s ordinary tests, which wait for it through
`whole::swept`. Written first in `whole`'s own tests, it ran there with the
sweep inline, on Windows (the command above, `-- --nocapture whole::`)
and on the Linux build machine (`cargo test -j 8 --all-features --
--test-threads 8 --nocapture whole::`):

```text
Windows
the first write: own 80.8786ms, clock 90.2605ms; the slowest of 20 others: own 2.489327ms, clock 5.9527ms
test whole::tests::the_first_write_into_a_full_directory_waits_for_no_sweep ... FAILED
test result: FAILED. 4 passed; 1 failed; 0 ignored; 0 measured; 34 filtered out; finished in 45.73s
Linux
the first write: own 8.832285ms, clock 23.993264ms; the slowest of 20 others: own 182.814µs, clock 19.35415ms
test whole::tests::the_first_write_into_a_full_directory_waits_for_no_sweep ... FAILED
test result: FAILED. 4 passed; 1 failed; 0 ignored; 0 measured; 34 filtered out; finished in 1.04s
```

With the sweep beside the write, three runs on each, still in `whole`'s
tests, the file system calls still counted as Xmip's:

```text
Windows
the first write: own 2.148626ms, clock 44.0863ms; the slowest of 20 others: own 2.09552ms, clock 8.5105ms
the first write: own 2.284627ms, clock 17.302ms; the slowest of 20 others: own 2.335132ms, clock 31.2859ms
the first write: own 3.081258ms, clock 26.4283ms; the slowest of 20 others: own 2.725427ms, clock 40.7225ms
Linux
the first write: own 218.008µs, clock 14.022578ms; the slowest of 20 others: own 200.081µs, clock 15.434467ms
the first write: own 173.663µs, clock 14.12854ms; the slowest of 20 others: own 169.999µs, clock 15.321796ms
the first write: own 172.635µs, clock 12.9271ms; the slowest of 20 others: own 164.953µs, clock 15.280856ms
```

`test/Timing.Test.ps1` had passed with it there: it held its bound beside
the writes after it, which the check leaves to a timing program, and the
check read no `Spent`. It now refuses `Spent::begin` in a test's module
outside a timing program (the production code that opens an account, and
`spent.rs`'s own arithmetic, stay out of it): with the test in `whole.rs`,
`Invoke-Pester -Path test/Timing.Test.ps1` said

```text
Expected 0, because each belongs in its module's measured program (rust-style.md 5c):
module/core/operation/archive/.src/whole.rs:313, but got 1.
Passed 7 Failed 1
```

and, the test moved to the timing program, `Passed 8 Failed 0`. There,
by the estate's command (`Test-XmipMeasuredProgram -ManifestPath
module/core/operation/archive/Cargo.toml -Feature test-support -Through
@('--config', '.local-work/landing/patch.toml')`, linted and run alone),
`test result: ok. 1 passed`; by hand with `--nocapture`, on Windows before
the file system calls ran as I/O, and after:

```text
before
the first write: own 1.518408ms, clock 9.5755ms; the slowest of 20 others: own 1.602214ms, clock 24.7371ms
the first write: own 1.766567ms, clock 11.2269ms; the slowest of 20 others: own 1.829666ms, clock 21.4861ms
the first write: own 1.797202ms, clock 24.0717ms; the slowest of 20 others: own 1.734598ms, clock 74.4714ms
after
the first write: own 157.405µs, clock 21.9663ms; the slowest of 20 others: own 126.701µs, clock 16.063ms
the first write: own 233.016µs, clock 38.2316ms; the slowest of 20 others: own 137.308µs, clock 93.8461ms
the first write: own 262.024µs, clock 30.7098ms; the slowest of 20 others: own 142.612µs, clock 21.575ms
```

and on the Linux build machine after (`cargo test -j 8 --test measured
--features test-support -- --test-threads=1 --nocapture`; one run before
gave `own 473.534µs` and `371.093µs`):

```text
the first write: own 79.001µs, clock 19.305102ms; the slowest of 20 others: own 33.415µs, clock 20.99679ms
the first write: own 73.921µs, clock 19.162031ms; the slowest of 20 others: own 35.849µs, clock 24.057893ms
the first write: own 93.556µs, clock 19.609447ms; the slowest of 20 others: own 39.886µs, clock 20.721566ms
```

The first write's own share is the others' and the thread it starts.
Its clock is mostly the disk's two syncs, which the millisecond rule does
not hold (ADR-0018, amendment 2026-11-09); on Windows it also waits on the
listing of the same directory, as the cost above says. The clock is
printed, not asserted: one write against the slowest of twenty is
outlasted by chance. The program takes 26 to 36 seconds on Windows, of
which the 50,000 items are 18 to 23, and about a second on Linux; made on
eight threads, the items came no faster on Windows and slower on Linux.

After the change, the same command in each crate, with `cargo clippy
--all-targets --all-features -- -D warnings` and `cargo fmt --check` clean
in each, on Windows:

```text
module/core/library/file               test result: ok. 8 passed; 0 failed
module/core/operation/archive          test result: ok. 38 passed; 0 failed
module/core/operation/archive/file     test result: ok. 16 passed; 0 failed
module/core/operation/archive/parquet  test result: ok. 9 passed; 0 failed
module/core/operation/archive/sql      test result: ok. 15 passed; 0 failed
```

And on the Linux build machine (`cargo test -j 8 --all-features --
--test-threads 8`, the estate patched to its working trees), clippy as
above clean:

```text
module/core/library/file               test result: ok. 9 passed; 0 failed
module/core/operation/archive          test result: ok. 38 passed; 0 failed
module/core/operation/archive/file     test result: ok. 16 passed; 0 failed
module/core/operation/archive/parquet  test result: ok. 9 passed; 0 failed
module/core/operation/archive/sql      test result: ok. 15 passed; 0 failed
```
