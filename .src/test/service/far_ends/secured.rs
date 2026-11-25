//! The far ends that check the secret a node presents: the login a broker
//! or a server requires — AMQP's, `RabbitMQ`'s, `ActiveMQ`'s, FTP's and
//! SMB's (ADR-0019, amendment 2026-11-25) — and the vendors' transports,
//! AWS's Signature Version 4, Azure's Shared Key and Shared Access
//! Signature, Google's bearer token (ADR-0015, amendment 2026-11-25). Each
//! is its crate's own loopback far end, stood checking a value this test
//! draws ([`super::drawn`]), never one written down; the node's Send Port
//! names the secret `linked.<name>`, and the test sets it to that value
//! through the node, as an operator sets one (`linked.rs`), so the node
//! presents it from its Administration Database as it connects. Where the
//! protocol names who presents it — a user, an access key ID, a shared
//! access policy, an account — the Send Port names the one the far end
//! holds.
//!
//! The vendors' are linked without TLS, as HTTP is, so their endpoint is
//! `http://`.

use super::{Standing, stood};

/// The far ends this build links that check a secret, in the order of
/// their names.
pub(super) fn every(all: &mut Vec<Standing>) {
    standing! {all, "transport-activemq", "activemq",
    |drawn| stood(xmip_transport_activemq::ActiveMqTransport::loopback()
        .logging_in(xmip_transport::Login::new("probe", &drawn))),
    "activemq://{far}", ["destination" = "/queue/probe", "user" = "probe"], false}
    standing! {all, "transport-amqp", "amqp",
    |drawn| stood(xmip_transport_amqp::AmqpTransport::loopback()
        .logging_in(xmip_transport::Login::new("probe", &drawn))),
    "amqp://{far}", ["user" = "probe"], false}
    standing! {all, "transport-aws-kinesis", "aws-kinesis",
    |drawn| stood(xmip_transport_aws_kinesis::KinesisTransport::loopback()
        .with_credentials("probe-key", &drawn)),
    "aws-kinesis://http://{far}",
    ["region" = "eu-north-1", "stream" = "orders", "access_key_id" = "probe-key"], false}
    standing! {all, "transport-aws-s3", "aws-s3",
    |drawn| stood(xmip_transport_aws_s3::S3Transport::loopback()
        .with_credentials("probe-key", &drawn)),
    "aws-s3://http://{far}",
    ["region" = "eu-north-1", "bucket" = "probe", "access_key_id" = "probe-key"], false}
    standing! {all, "transport-aws-sns", "aws-sns",
    |drawn| stood(xmip_transport_aws_sns::SnsTransport::loopback()
        .with_credentials("probe-key", &drawn)),
    "aws-sns://http://{far}",
    ["region" = "eu-north-1", "topic_arn" = "arn:aws:sns:eu-north-1:123456789012:loopback",
     "access_key_id" = "probe-key"], false}
    standing! {all, "transport-aws-sqs", "aws-sqs",
    |drawn| stood(xmip_transport_aws_sqs::SqsTransport::loopback()
        .with_credentials("probe-key", &drawn)),
    "aws-sqs://{far}", ["region" = "eu-north-1", "access_key_id" = "probe-key"], false}
    standing! {all, "transport-azure-blob", "azure-blob",
    |drawn| stood(xmip_transport_azure_blob::AzureBlobTransport::loopback().with_key(&drawn)),
    "azure-blob://http://{far}", ["account" = "probe", "container" = "probe"], false}
    standing! {all, "transport-azure-event-grid", "azure-event-grid",
    |drawn| stood(xmip_transport_azure_event_grid::EventGridTransport::loopback()
        .with_key(&drawn)),
    "azure-event-grid://http://{far}/api/events", [], false}
    standing! {all, "transport-azure-event-hubs", "azure-event-hubs",
    |drawn| stood(xmip_transport_azure_event_hubs::EventHubsTransport::loopback()
        .with_policy("RootManageSharedAccessKey", &drawn)),
    "azure-event-hubs://http://{far}",
    ["hub" = "telemetry", "key_name" = "RootManageSharedAccessKey"], false}
    standing! {all, "transport-azure-service-bus", "azure-service-bus",
    |drawn| stood(xmip_transport_azure_service_bus::ServiceBusTransport::loopback()
        .with_policy("RootManageSharedAccessKey", &drawn)),
    "azure-service-bus://http://{far}",
    ["queue" = "orders", "key_name" = "RootManageSharedAccessKey"], false}
    standing! {all, "transport-ftp", "ftp",
    |drawn| stood(xmip_transport_ftp::FtpTransport::loopback()
        .logging_in(xmip_transport::Login::new("xmip", &drawn))),
    "ftp://xmip@{far}", [], false}
    standing! {all, "transport-google-cloud-storage", "google-cloud-storage",
    |drawn| stood(xmip_transport_google_cloud_storage::GcsTransport::loopback()
        .with_token(&drawn)),
    "google-cloud-storage://http://{far}", ["bucket" = "probe"], false}
    standing! {all, "transport-google-pub-sub", "google-pub-sub",
    |drawn| stood(xmip_transport_google_pub_sub::PubSubTransport::loopback()
        .with_token(&drawn)),
    "google-pub-sub://http://{far}", ["project" = "probe", "topic" = "probe"], false}
    standing! {all, "transport-rabbitmq", "rabbitmq",
    |drawn| stood(xmip_transport_rabbitmq::RabbitMqTransport::loopback()
        .logging_in(xmip_transport::Login::new("probe", &drawn))),
    "rabbitmq://{far}", ["queue" = "probe", "user" = "probe"], false}
    standing! {all, "transport-smb", "smb",
    |drawn| stood(xmip_transport_smb::SmbTransport::loopback()
        .admitting(xmip_transport::Login::new("probe", &drawn))),
    "smb://{far}", ["share" = "xmip", "user" = "probe"], false}
}
