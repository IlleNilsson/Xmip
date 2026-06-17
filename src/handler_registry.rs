use crate::handler::{HandlerDescriptor, HandlerKind};
use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RegisteredHandler {
    pub descriptor: HandlerDescriptor,
    pub module_component_id: String,
    pub binary_path: String,
}

#[derive(Debug, Default)]
pub struct HandlerRegistry {
    handlers: HashMap<String, RegisteredHandler>,
}

impl HandlerRegistry {
    pub fn new() -> Self {
        Self {
            handlers: HashMap::new(),
        }
    }

    pub fn register(&mut self, handler: RegisteredHandler) {
        self.handlers
            .insert(handler.descriptor.name.clone(), handler);
    }

    pub fn get(&self, handler_name: &str) -> Option<&RegisteredHandler> {
        self.handlers.get(handler_name)
    }

    pub fn list(&self) -> Vec<&RegisteredHandler> {
        self.handlers.values().collect()
    }

    pub fn list_by_kind(&self, kind: HandlerKind) -> Vec<&RegisteredHandler> {
        self.handlers
            .values()
            .filter(|handler| handler.descriptor.kind == kind)
            .collect()
    }
}
