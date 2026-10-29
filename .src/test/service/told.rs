//! The service is told, never looks (the millisecond rule; ADR-0018,
//! amendment 2026-10-17): an order left where it takes them is acted on
//! the moment the operating system says it arrived, and a service nothing
//! tells uses next to no processor.
//!
//! What is held for an order is the fastest round in every five
//! (`xcore::latency`), beside the machine's own wake measured round by
//! round under the same load: a poll is in every round, a wake that waited
//! its turn for a processor in some only. The order measured is a pause of
//! a Subscription already paused, which the node answers from what it
//! holds, so the round is the telling and not Xmip Storage's write of a
//! pause. From the order left to its answer heard, four threads are woken
//! — the service's watch, the service's own, the test's reader of its
//! output and the test — and the order's file is read and removed
//! (`observe::Order::take`), the load an order carries, measured beside it
//! by taking the same order from a directory of the test's own. So the
//! round is held under the millisecond plus that take plus four plain
//! wakes.

use xmip_core::latency::{FIVE, PlainWake, spread};

use super::*;

/// How many orders are measured.
const ROUNDS: usize = 4 * FIVE;

/// The bound: about a millisecond.
const BOUND: Duration = Duration::from_millis(1);

/// The most processor time a service nothing tells may use in a second:
/// its publication's round, four a second (ADR-0018, amendment
/// 2026-09-30), and nothing else. Each round builds the publication and
/// writes it whole, and on Windows the file system's filters run on the
/// writing thread: measured 2026-10-17 at 0 to 80 ms a second, in steps of
/// the 15.6 ms Windows counts processor time in. Without the round it is
/// none.
const IDLE: Duration = Duration::from_millis(100);

/// Start the service in a directory named for `name`, its Locations
/// started where `starts` says, and wait until it accepts work.
fn started(name: &str, starts: bool) -> (PathBuf, Child, Ending, Receiver<String>) {
    let directory =
        std::env::temp_dir().join(format!("xmip-service-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let configuration = written(&directory, &unheld().to_string());
    if !starts {
        let text = std::fs::read_to_string(&configuration).expect("reads");
        std::fs::write(
            &configuration,
            text.replace("address = ", "start = false\naddress = "),
        )
        .expect("writes");
    }
    let mut child = spawned(&configuration, &directory);
    let ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(
        &said,
        &format!("{} accepts work", node_scope()),
        Duration::from_secs(10),
    );
    (directory, child, ending, said)
}

/// Stop the service, and remove what it left.
fn ended(directory: &Path, child: Child, mut ending: Ending, said: &Receiver<String>) {
    stop(&child);
    heard(said, "stopped by the console", Duration::from_secs(5));
    assert!(exited(child, Duration::from_secs(5)).success());
    ending.0 = None;
    let _ = std::fs::remove_dir_all(directory);
}

#[test]
fn an_order_is_acted_on_the_moment_it_is_left() {
    let _machine = alone();
    let (directory, child, ending, said) = started("told", true);
    let operator = operator();
    let plain = PlainWake::start();

    order(&directory, Act::Pause);
    let paused = heard(&said, "paused by", Duration::from_secs(2));
    assert!(paused.contains(&operator), "{paused}");

    let beside = directory.join("beside");
    let (mut taken, mut woke, mut files) = (Vec::new(), Vec::new(), Vec::new());
    for _ in 0..ROUNDS {
        order(&directory, Act::Pause);
        let left = Instant::now();
        heard(&said, "was already paused", Duration::from_secs(2));
        taken.push(left.elapsed());
        woke.push(plain.round().0);
        files.push(file_taken(&beside));
    }

    let taken = spread("an order left to its answer heard", taken);
    let usual = spread("a plain channel beside it", woke).fastest_of_five;
    let file = spread("its file read and removed beside it", files).fastest_of_five;
    assert!(
        taken.fastest_of_five < BOUND + file + usual * 4,
        "the fastest of five {:?}, its file {file:?}, the machine's own wake {usual:?}",
        taken.fastest_of_five
    );
    ended(&directory, child, ending, &said);
}

/// How long the order's own file takes to read and remove: the same order
/// left in `beside` and taken by observe's one taker, as the service takes
/// it.
fn file_taken(beside: &Path) -> Duration {
    Order {
        node: node_scope(),
        noun: Noun::Subscription,
        target: "onward".to_string(),
        act: Act::Pause,
        who: operator(),
    }
    .leave(beside)
    .expect("the order is left");
    let began = Instant::now();
    let taken = Order::take(beside, &node_scope());
    let took = began.elapsed();
    assert_eq!(taken.len(), 1);
    took
}

#[test]
fn a_service_nothing_tells_uses_next_to_no_processor() {
    let _machine = alone();
    // Nothing started, so what is measured is the service's own: a
    // Receive Location's transport waits on its own terms.
    let (directory, child, ending, said) = started("idle", false);

    // What its start set going — its Storage node's own work — settles.
    std::thread::sleep(Duration::from_secs(1));
    let from = processor_time(&child);
    let began = Instant::now();
    std::thread::sleep(Duration::from_secs(1));
    let used = processor_time(&child).saturating_sub(from);
    let over = began.elapsed();
    println!("an idle service used {used:?} of processor time in {over:?}");
    // Held per second of the window read: the second reading is taken as
    // PowerShell starts, which on a busy machine is seconds past the sleep.
    let bound = IDLE.mul_f64(over.as_secs_f64().max(1.0));
    assert!(
        used < bound,
        "an idle service used {used:?} of processor time in {over:?}, over {bound:?}"
    );
    ended(&directory, child, ending, &said);
}

/// The processor time the service's process has used, as Windows counts
/// it for every process (`TotalProcessorTime`). Reading another process's
/// counters is a call into kernel32 no safe Rust crate makes, and this
/// estate writes no unsafe outside the files it lists (ADR-0050), so
/// PowerShell reads it, as it presses Ctrl+Break.
#[cfg(windows)]
fn processor_time(child: &Child) -> Duration {
    let script = format!("(Get-Process -Id {}).TotalProcessorTime.Ticks", child.id());
    let read = Command::new("pwsh")
        .args(["-NoProfile", "-NonInteractive", "-Command", &script])
        .output()
        .expect("pwsh runs");
    let ticks: u64 = String::from_utf8_lossy(&read.stdout)
        .trim()
        .parse()
        .expect("a count of ticks");
    Duration::from_nanos(ticks * 100)
}

/// The processor time the service's process has used, user and system,
/// in the clock ticks Linux counts (`/proc/<pid>/stat`, a hundred a
/// second).
#[cfg(target_os = "linux")]
fn processor_time(child: &Child) -> Duration {
    let stat = std::fs::read_to_string(format!("/proc/{}/stat", child.id())).expect("its stat");
    // The fields after the command, which is in parentheses and may hold
    // spaces: state is the first, user time the twelfth, system the
    // thirteenth.
    let after = &stat[stat.rfind(')').expect("a command") + 2..];
    let fields: Vec<&str> = after.split_whitespace().collect();
    let ticks: u64 =
        fields[11].parse::<u64>().expect("user") + fields[12].parse::<u64>().expect("system");
    Duration::from_millis(ticks * 10)
}

/// The processor time the service's process has used, as `ps` says it:
/// `minutes:seconds.hundredths`.
#[cfg(all(unix, not(target_os = "linux")))]
fn processor_time(child: &Child) -> Duration {
    let read = Command::new("ps")
        .args(["-o", "time=", "-p", &child.id().to_string()])
        .output()
        .expect("ps runs");
    let text = String::from_utf8_lossy(&read.stdout);
    let (minutes, seconds) = text.trim().split_once(':').expect("minutes:seconds");
    let minutes: u64 = minutes.parse().expect("minutes");
    let seconds: f64 = seconds.parse().expect("seconds");
    Duration::from_secs(minutes * 60) + Duration::from_secs_f64(seconds)
}
