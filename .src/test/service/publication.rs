//! The node publishes its snapshot where it declares (ADR-0018, amendment
//! 2026-09-30): its health, figures and topology, its Subscription and where
//! it takes orders, read by observe's one reader — the function the
//! runtime's library forwards to every .NET surface as
//! `xmip_publication_read_v1`. A pause left where the snapshot says, as a
//! surface leaves it, shows paused in the next snapshot, published at once
//! and not a round later; the stop leaves the node Done and the pause
//! standing.

use xmip_observe::{Counted, Health, NodeKind, PauseState, Publication};

use super::*;

/// The publication at `path` once `holds` says it holds, within `bound`,
/// and how long that took. Bounded, and never a sleep.
fn published_until(
    path: &Path,
    bound: Duration,
    holds: impl Fn(&Publication) -> bool,
) -> (Publication, Duration) {
    let began = Instant::now();
    loop {
        let read = std::fs::read_to_string(path)
            .ok()
            .and_then(|text| Publication::read(&text).ok());
        match read {
            Some(publication) if holds(&publication) => return (publication, began.elapsed()),
            Some(publication) if began.elapsed() > bound => {
                panic!(
                    "{} never held within {bound:?}: {publication:?}",
                    path.display()
                )
            }
            None if began.elapsed() > bound => panic!("nothing published at {}", path.display()),
            _ => std::thread::yield_now(),
        }
    }
}

/// The Subscription `onward`'s standing in `publication`.
fn onward(publication: &Publication) -> Option<PauseState> {
    let node = node_scope();
    publication
        .subscriptions
        .iter()
        .find(|subscription| subscription.node == node && subscription.name == "onward")
        .map(|subscription| subscription.state)
}

fn mood(publication: &Publication, scope: &str) -> Option<Health> {
    publication
        .records
        .iter()
        .find(|record| record.scope == scope)
        .map(|record| record.health)
}

/// What the first publication says: the node at its location, published
/// by the service, where it takes orders, every record Fine, the
/// Subscription active, and the node drawn with its Parties.
fn as_it_starts(first: &Publication) {
    let node = node_scope();
    assert_eq!(first.node, node);
    assert_eq!(first.source, "xmip-service");
    assert!(
        Path::new(&first.orders).ends_with(Path::new("data").join("orders")),
        "{}",
        first.orders
    );
    assert_eq!(onward(first), Some(PauseState::Active));
    for scope in [
        node.clone(),
        format!("{node}/system-process"),
        format!("{node}/capability"),
        format!("{node}/receive/In"),
        format!("{node}/send/Out"),
        format!("{node}/process/onward"),
    ] {
        assert_eq!(mood(first, &scope), Some(Health::Fine), "{scope}");
    }
    let drawn = first.topology.clone().expect("the node is drawn");
    let at = format!("node/{}", node_name());
    for (id, kind) in [
        ("cluster".to_string(), NodeKind::Cluster),
        (at.clone(), NodeKind::Node),
        (format!("{at}/receive/In"), NodeKind::Endpoint),
        (format!("{at}/process"), NodeKind::Stage),
        (format!("{at}/send/Out"), NodeKind::Endpoint),
        ("party/sending/any-party".to_string(), NodeKind::Party),
        ("party/receiving/any-party".to_string(), NodeKind::Party),
    ] {
        assert!(
            drawn
                .nodes
                .iter()
                .any(|node| node.id == id && node.kind == kind),
            "{id} drawn as {}: {:?}",
            kind.word(),
            drawn.nodes
        );
    }
}

/// What `publication` counted of `counted` at `scope`, or none.
fn count(publication: &Publication, scope: &str, counted: Counted) -> u64 {
    publication
        .counts
        .iter()
        .find(|count| count.scope == scope && count.counted == counted)
        .map_or(0, |count| count.value)
}

#[test]
fn the_node_publishes_its_snapshot_and_a_pause_left_where_it_says_shows_in_the_next() {
    let directory =
        std::env::temp_dir().join(format!("xmip-service-publication-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let receive = free_address();
    let configuration = written(&directory, &receive);
    let snapshot = directory.join("data").join("snapshot.toml");
    let node = node_scope();

    let mut child = spawned(&configuration, &directory);
    let mut ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(&said, "publishes its snapshot at", Duration::from_secs(10));
    heard(
        &said,
        &format!("{node} accepts work"),
        Duration::from_secs(10),
    );
    let declared = declarations(&directory);
    assert!(
        declared.iter().any(|text| text.contains("snapshot = ")
            && text.contains("snapshot.toml")
            && text.contains(&format!("location = \"{node}\""))),
        "the service declares where it publishes: {declared:?}"
    );

    // Published before it accepts work, at its own location, with where it
    // takes orders.
    let (first, _) = published_until(&snapshot, Duration::from_secs(1), |_| true);
    as_it_starts(&first);

    // What it received is counted at the stage that counts it, and what its
    // gate refused as failed, in a publication within a round.
    for message in 0..MESSAGES {
        deliver(&receive, format!("order {message}").as_bytes());
    }
    published_until(&snapshot, Duration::from_secs(5), |publication| {
        count(publication, &format!("{node}/receive"), Counted::Streams) == MESSAGES
            && count(publication, &node, Counted::Failed) == MESSAGES
    });

    // A pause left where the publication says, as a surface leaves it.
    Order {
        node: first.node.clone(),
        noun: Noun::Subscription,
        target: "onward".to_string(),
        act: Act::Pause,
        who: operator(),
    }
    .leave(Path::new(&first.orders))
    .expect("the order is left");
    let (paused, took) = published_until(&snapshot, Duration::from_secs(2), |publication| {
        onward(publication) == Some(PauseState::Paused)
    });
    // Taken at the next look, ten milliseconds, and published at once: not
    // a round of a quarter of a second later.
    assert!(
        took < Duration::from_millis(250),
        "published paused in {took:?}"
    );
    assert_eq!(
        mood(&paused, &format!("{node}/process/onward")),
        Some(Health::Paused)
    );
    let by = paused
        .subscriptions
        .iter()
        .find(|subscription| subscription.name == "onward")
        .map(|subscription| subscription.by.clone());
    assert_eq!(by, Some(operator()));

    stop(&child);
    heard(&said, "stopped by the console", Duration::from_secs(5));
    assert!(exited(child, Duration::from_secs(5)).success());
    ending.0 = None;

    // What it leaves says it stopped, and the pause stands.
    let (left, _) = published_until(&snapshot, Duration::from_secs(1), |_| true);
    assert_eq!(mood(&left, &node), Some(Health::Done));
    assert_eq!(
        mood(&left, &format!("{node}/system-process")),
        Some(Health::Done)
    );
    assert_eq!(onward(&left), Some(PauseState::Paused));
    let stopped = left.records.iter().find(|record| record.scope == node);
    assert!(
        stopped.is_some_and(|record| record.evidence.starts_with("stopped by the console")),
        "{stopped:?}"
    );
    let _ = std::fs::remove_dir_all(&directory);
}
