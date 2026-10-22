//! The cluster's authority served by the node that keeps it: the premises'
//! own ACME service (ADR-0034, amendment 2026-10-22). Where the node's
//! `[provision.node]` names `xmip-core-provision-internal-ca` and `serve`,
//! `xmip-service` answers ACME (RFC 8555, with ACME Renewal Information,
//! RFC 9773) there for every client on the premises — the cluster's other
//! nodes and any third party's — and, where it names `publish`, its
//! revocation list and certificate over plain HTTP, both until the node
//! drains. Provisioning beside the node's path, never on it (ADR-0045
//! clause 1): nothing here reaches beyond the cluster.
//!
//! The authority is kept beside the configuration, in the folder
//! `authority` names, `authority` unless said: the folder every surface
//! inspects, revokes from and backs up (`xmip certificate`,
//! `Get-XmipCertificate`).

use std::path::Path;

use xmip_configure::XmipConfigurationDocument;
use xmip_core::settings::Given;

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

/// The listeners `[provision.node]` names for the authority, each its
/// address and what it is: what `--listening` opens a firewall for.
pub fn listens(document: &XmipConfigurationDocument) -> Vec<(String, &'static str)> {
    let Some(table) = document.provision.get(NODE) else {
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

/// Serve the authority `document`, the configuration at `configuration`,
/// names; `None` where it names none to serve.
///
/// # Errors
///
/// The table is refused, the authority cannot be kept, or an address
/// cannot be bound; or this build does not link the cluster's authority.
pub fn serve(
    document: &XmipConfigurationDocument,
    configuration: &Path,
) -> Result<Option<Served>, String> {
    if listens(document).is_empty() {
        return Ok(None);
    }
    served(document, configuration).map(Some)
}

#[cfg(feature = "provision-internal-ca")]
fn served(document: &XmipConfigurationDocument, configuration: &Path) -> Result<Served, String> {
    use xmip_provision_internal_ca::{InternalCa, SETTINGS};

    let said = |why: String| format!("[provision.{NODE}]: {why}");
    let table = document
        .provision
        .get(NODE)
        .map(xmip_configure::LocationSettings::given);
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

#[cfg(not(feature = "provision-internal-ca"))]
fn served(_: &XmipConfigurationDocument, _: &Path) -> Result<Served, String> {
    Err(format!(
        "[provision.{NODE}] serves the cluster's authority ({TECHNOLOGY}), which this build \
         does not link"
    ))
}
