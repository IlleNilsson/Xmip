//! The System Tests' Work Process unit *Order approval*, built by this crate
//! as well, so the root's service test runs it in `xmip-service`
//! (`.src/test/service/approved.rs`; open problem 87). One source, theirs:
//! the example `order_approval`, generated from their design
//! (`configuration/order-approval.bpmn`) by `process::generate` and held to
//! it by their test. It names the process capability `process`, which this
//! crate calls `xmip-process`; the name is given here, at the crate root,
//! where it reaches the unit's module.

extern crate xmip_process as process;

#[path = "../../test/core/system-test/examples/order_approval.rs"]
mod unit;
