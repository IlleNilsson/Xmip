//! `--install`'s last step: the command line's document, `cli.toml`, beside
//! the installed programs where there is none, stating the node it
//! installed — `Surface = "local"` at the local endpoint its configuration
//! names (`registration::local_endpoint`, which the node's service
//! definition was given) — so `xmip` on the machine follows that node with
//! no option given (ADR-0052 clause 3). It names no `AuditDirectory`: the
//! audit capability decides. It is written in the words the command line
//! reads it by (`xmip-core-operate`'s `surface::choice::table`), through
//! configure's one writer. A document already there is the operator's and
//! is never written over, and `--uninstall` leaves it, as it leaves the
//! node's configuration (ADR-0040).

use std::fs::OpenOptions;
use std::io::{ErrorKind, Write};
use std::path::Path;

use xmip_operate::surface::choice::table::{COMMAND_LINE, local_document};
use xmip_runtime::registration::ServiceDefinition;

/// The command line's document beside the programs of `service`, the
/// node's Xmip Service, where there is none: what `--install` says of it,
/// after the service.
///
/// # Errors
/// The document cannot be written.
pub fn place(service: &ServiceDefinition) -> Result<String, String> {
    let Some(endpoint) = &service.local else {
        return Ok(String::new());
    };
    let bin = Path::new(&service.executable)
        .parent()
        .unwrap_or_else(|| Path::new("."));
    let path = bin.join(COMMAND_LINE);
    Ok(if placed(&path, endpoint)? {
        format!("; xmip follows it, as {} says", path.display())
    } else {
        format!("; {} was there and is kept", path.display())
    })
}

/// The document at `path` stating the node on this machine at `endpoint`,
/// written where there is none: whether it was.
fn placed(path: &Path, endpoint: &str) -> Result<bool, String> {
    let said = |error: std::io::Error| format!("{}: {error}", path.display());
    let text = local_document(endpoint)?;
    // Made only where nothing is, in the one call: never over the
    // operator's.
    let mut file = match OpenOptions::new().write(true).create_new(true).open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == ErrorKind::AlreadyExists => return Ok(false),
        Err(error) => return Err(said(error)),
    };
    if let Err(error) = file.write_all(text.as_bytes()) {
        // Half a document would be kept by the next install: none is.
        drop(file);
        let _ = std::fs::remove_file(path);
        return Err(said(error));
    }
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use xmip_operate::surface::choice::{Asked, Choice, Document, SurfaceLine, decided};
    use xmip_runtime::registration::local_endpoint;

    fn bin(name: &str) -> xmip_file::temporary::Folder {
        xmip_file::temporary::Folder::new(&format!("service-cli-{name}"))
    }

    fn endpoint() -> String {
        local_endpoint(&xmip_configure::fixture::test_cluster().node(0).name, None)
    }

    #[test]
    fn it_is_written_where_there_is_none_and_read_as_the_node_on_this_machine() {
        let bin = bin("written");
        let path = bin.join(COMMAND_LINE);

        assert_eq!(placed(&path, &endpoint()), Ok(true));
        let document = Document::read(&path);
        assert_eq!(
            decided(&Asked::Stated(SurfaceLine::default()), &document, false),
            Ok(Choice::Local(Some(endpoint())))
        );
        assert_eq!(document.value("AuditDirectory"), None);
    }

    #[test]
    fn an_operator_s_document_is_never_written_over() {
        let bin = bin("kept");
        let path = bin.join(COMMAND_LINE);
        let operator_s = "[Xmip]\nSurface = \"snapshot\"\nSnapshot = \"a.xmip\"\n";
        std::fs::write(&path, operator_s).expect("the operator's");

        assert_eq!(placed(&path, &endpoint()), Ok(false));
        assert_eq!(std::fs::read_to_string(&path).expect("read"), operator_s);
    }

    #[test]
    fn the_node_s_service_places_it_beside_its_program() {
        let bin = bin("service");
        let node = xmip_configure::fixture::test_cluster().node(0).name.clone();
        let service = ServiceDefinition::for_node(
            &node,
            &bin.join("xmip-service").display().to_string(),
            "node.xmip",
            ".",
        )
        .serving_at(&endpoint());

        let said = place(&service).expect("placed");

        assert!(said.contains("xmip follows it"), "{said}");
        assert!(bin.join(COMMAND_LINE).is_file());
        assert!(
            place(&service)
                .expect("kept")
                .contains("was there and is kept")
        );
    }
}
