use crate::runtime_message::{RuntimeInterchange, RuntimeMessage, RuntimeSection};
use crate::runtime_store::RuntimeStore;
use std::sync::mpsc::{self, Receiver, Sender};
use std::thread;
use uuid::Uuid;

#[derive(Debug, Clone)]
pub enum RuntimeCommand {
    IngressStream {
        receive_location: String,
        stream: Vec<u8>,
    },
    Stop,
}

#[derive(Debug, Clone)]
pub enum RuntimeWork {
    Received(RuntimeMessage),
    Interpreted(RuntimeMessage),
    Published(RuntimeMessage),
    Stop,
}

pub struct ThreadedRuntime {
    ingress: Sender<RuntimeCommand>,
}

impl ThreadedRuntime {
    pub fn start(store: RuntimeStore) -> Self {
        let (ingress_tx, ingress_rx) = mpsc::channel();
        let (interpret_tx, interpret_rx) = mpsc::channel();
        let (publish_tx, publish_rx) = mpsc::channel();
        let (dispatch_tx, dispatch_rx) = mpsc::channel();

        spawn_receive_worker(store.clone(), ingress_rx, interpret_tx);
        spawn_interpret_worker(store.clone(), interpret_rx, publish_tx);
        spawn_publish_worker(store.clone(), publish_rx, dispatch_tx);
        spawn_dispatch_worker(store, dispatch_rx);

        Self { ingress: ingress_tx }
    }

    pub fn submit_stream(&self, receive_location: String, stream: Vec<u8>) {
        self.ingress
            .send(RuntimeCommand::IngressStream {
                receive_location,
                stream,
            })
            .expect("failed to submit stream to runtime");
    }

    pub fn stop(&self) {
        let _ = self.ingress.send(RuntimeCommand::Stop);
    }
}

fn spawn_receive_worker(
    store: RuntimeStore,
    input: Receiver<RuntimeCommand>,
    output: Sender<RuntimeWork>,
) {
    thread::spawn(move || {
        for command in input {
            match command {
                RuntimeCommand::IngressStream {
                    receive_location,
                    stream,
                } => {
                    let message_id = Uuid::new_v4().to_string();
                    let interchange_id = Uuid::new_v4().to_string();
                    let section_id = Uuid::new_v4().to_string();

                    let message = RuntimeMessage {
                        message_id: message_id.clone(),
                        interchange_chain: vec![interchange_id.clone()],
                        current_interchange_id: interchange_id.clone(),
                        sections: vec![RuntimeSection {
                            section_id,
                            stream_reference: receive_location,
                            stream_bytes: stream,
                        }],
                        promoted_properties: Vec::new(),
                    };

                    let interchange = RuntimeInterchange {
                        interchange_id: interchange_id.clone(),
                        parent_interchange_id: String::new(),
                        root_interchange_id: interchange_id.clone(),
                        message_ids: vec![message_id.clone()],
                        events: vec!["entry".to_string()],
                    };

                    store.save_message(&message_id, &message).expect("message store failed");
                    store
                        .save_interchange(&interchange_id, &interchange)
                        .expect("interchange store failed");
                    store.audit("entry").expect("audit failed");

                    output
                        .send(RuntimeWork::Received(message))
                        .expect("receive worker output failed");
                }
                RuntimeCommand::Stop => {
                    let _ = output.send(RuntimeWork::Stop);
                    break;
                }
            }
        }
    });
}

fn spawn_interpret_worker(
    store: RuntimeStore,
    input: Receiver<RuntimeWork>,
    output: Sender<RuntimeWork>,
) {
    thread::spawn(move || {
        for work in input {
            match work {
                RuntimeWork::Received(mut message) => {
                    message
                        .promoted_properties
                        .push("message.flow=stream-first".to_string());
                    message
                        .promoted_properties
                        .push("subscription.target=send-port".to_string());

                    store
                        .save_message(&message.message_id, &message)
                        .expect("interpreted message store failed");
                    store.audit("interpreted").expect("audit failed");

                    output
                        .send(RuntimeWork::Interpreted(message))
                        .expect("interpret worker output failed");
                }
                RuntimeWork::Stop => {
                    let _ = output.send(RuntimeWork::Stop);
                    break;
                }
                other => {
                    let _ = output.send(other);
                }
            }
        }
    });
}

fn spawn_publish_worker(store: RuntimeStore, input: Receiver<RuntimeWork>, output: Sender<RuntimeWork>) {
    thread::spawn(move || {
        for work in input {
            match work {
                RuntimeWork::Interpreted(message) => {
                    store.audit("published").expect("audit failed");
                    output
                        .send(RuntimeWork::Published(message))
                        .expect("publish worker output failed");
                }
                RuntimeWork::Stop => {
                    let _ = output.send(RuntimeWork::Stop);
                    break;
                }
                other => {
                    let _ = output.send(other);
                }
            }
        }
    });
}

fn spawn_dispatch_worker(store: RuntimeStore, input: Receiver<RuntimeWork>) {
    thread::spawn(move || {
        for work in input {
            match work {
                RuntimeWork::Published(message) => {
                    let action = if message
                        .promoted_properties
                        .iter()
                        .any(|value| value == "subscription.target=send-port")
                    {
                        "kick-off-send-port"
                    } else {
                        "kick-off-process"
                    };

                    store.audit(action).expect("audit failed");
                    store.audit("leaving").expect("audit failed");
                }
                RuntimeWork::Stop => break,
                _ => {}
            }
        }
    });
}
