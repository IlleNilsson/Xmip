//! The cluster's authority served by the node that keeps it: the premises'
//! own ACME service (ADR-0034, amendment 2026-10-22). Where the node's
//! `[provision.node]` names `xmip-core-provision-internal-ca` and `serve`,
//! `xmip-service` answers ACME (RFC 8555, with ACME Renewal Information,
//! RFC 9773) there for every client on the premises — the cluster's other
//! nodes and any third party's — and, where it names `publish`, its
//! revocation list and certificate over plain HTTP, both until the node
//! drains. Provisioning beside the node's path, never on it (ADR-0045
//! clause 1): nothing here reaches beyond the cluster. The node serves it
//! as it starts, by the `[provision.node]` of the slice it runs and never
//! of the file beside it, which may be a candidate it refused (`serve`;
//! ADR-0031, amendment 2026-11-12), said on the console and audited once it
//! accepts work (`said`).
//!
//! The authority is kept beside the configuration, in the folder
//! `authority` names, `authority` unless said: the folder every surface
//! inspects, revokes from and backs up (`xmip certificate`,
//! `Get-XmipCertificate`).

use std::collections::BTreeMap;
use std::path::Path;

use xmip_audit::program_audit::ProgramAudit;
use xmip_configure::LocationSettings;
use xmip_core::ExecutionPhase;
use xmip_core::settings::Given;

use crate::audit;

/// A node's `[provision]`, each purpose's table by its name.
type Provision = BTreeMap<String, LocationSettings>;

/// The technology whose table this serves.
const TECHNOLOGY: &str = "xmip-core-provision-internal-ca";

/// The purpose's table it reads, `[provision.node]`.
const NODE: &str = "node";

/// What the authority serves while the node runs; dropped, it stops.
pub struct Served {
    /// The ACME directory's URL.
    pub directory: String,
    /// Where its list and certificate are published, where they are.
    pub published: Option<String>,
    #[cfg(feature = "provision-internal-ca")]
    _held: (
        xmip_provision_internal_ca::Serving,
        Option<xmip_provision_internal_ca::Publishing>,
    ),
}

/// The listeners `[provision.node]` of `provision` names for the
/// authority, each its address and what it is: what `--listening` opens a
/// firewall for.
pub fn listens(provision: &Provision) -> Vec<(String, &'static str)> {
    let Some(table) = provision.get(NODE) else {
        return Vec::new();
    };
    let given = table.given();
    let text = |key: &str| {
        given.iter().find_map(|(name, value)| match value {
            Given::Text(text) if name == key => Some(text.clone()),
            _ => None,
        })
    };
    if text("source").as_deref() != Some(TECHNOLOGY) {
        return Vec::new();
    }
    [
        ("serve", "the cluster authority's ACME"),
        ("publish", "the cluster authority's list"),
    ]
    .into_iter()
    .filter_map(|(key, what)| text(key).map(|address| (address, what)))
    .collect()
}

/// Serve the authority `provision`, the `[provision]` of the slice the node
/// configured at `configuration` runs, names; `None` where it names none to
/// serve. Held until the node drains.
///
/// # Errors
///
/// The table is refused, the authority cannot be kept, or an address
/// cannot be bound; or this build does not link the cluster's authority.
pub fn serve(provision: &Provision, configuration: &Path) -> Result<Option<Served>, String> {
    if listens(provision).is_empty() {
        return Ok(None);
    }
    served(provision, configuration).map(Some)
}

/// Say where the cluster's authority `served` answers, on the console, and
/// audit it.
pub fn said(program: &str, audit: &ProgramAudit, served: &Served) {
    println!(
        "{program}: the cluster's authority answers ACME at {}",
        served.directory
    );
    if let Some(published) = &served.published {
        println!("{program}: the cluster's authority publishes its list at {published}");
    }
    audit::record(
        audit,
        "authority",
        ExecutionPhase::Begin,
        &[
            ("directory", served.directory.as_str()),
            ("published", served.published.as_deref().unwrap_or("")),
        ],
    );
}

cfg_select! {
    feature = "provision-internal-ca" => {
        fn served(provision: &Provision, configuration: &Path) -> Result<Served, String> {
            use xmip_provision_internal_ca::{InternalCa, SETTINGS};

            let said = |why: String| format!("[provision.{NODE}]: {why}");
            let table = provision.get(NODE).map(LocationSettings::given);
            let read = xmip_provision::read(NODE, &table.unwrap_or_default(), &[SETTINGS])
                .map_err(|refused| said(refused.to_string()))?;
            let ca = InternalCa::configured(&read.settings);
            let names = xmip_provision::names(&read.settings);
            let keep = configuration.parent().unwrap_or_else(|| Path::new("."));
            let serving = match ca.serves_on() {
                Some(listen) => ca
                    .serve(keep, listen, &names, None)
                    .map_err(|failure| said(failure.message))?,
                None => return Err(said("publish names no serve beside it".to_string())),
            };
            let publishing = ca
                .publishes_on()
                .map(|listen| ca.publish(keep, listen, &names))
                .transpose()
                .map_err(|failure| said(failure.message))?;
            Ok(Served {
                directory: serving.directory().to_string(),
                published: publishing
                    .as_ref()
                    .map(|it| format!("http://{}", it.address())),
                _held: (serving, publishing),
            })
        }
    }
    _ => {
        fn served(_: &Provision, _: &Path) -> Result<Served, String> {
            Err(format!(
                "[provision.{NODE}] serves the cluster's authority ({TECHNOLOGY}), which this \
                 build does not link"
            ))
        }
    }
}
