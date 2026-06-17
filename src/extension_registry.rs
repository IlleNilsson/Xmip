use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RegisteredExtension {
    pub extension_name: String,
    pub module_component_id: String,
    pub binary_path: String,
    pub entry_symbol: String,
}

#[derive(Debug, Default)]
pub struct ExtensionRegistry {
    extensions: HashMap<String, RegisteredExtension>,
}

impl ExtensionRegistry {
    pub fn new() -> Self {
        Self {
            extensions: HashMap::new(),
        }
    }

    pub fn register(&mut self, extension: RegisteredExtension) {
        self.extensions
            .insert(extension.extension_name.clone(), extension);
    }

    pub fn get(&self, extension_name: &str) -> Option<&RegisteredExtension> {
        self.extensions.get(extension_name)
    }

    pub fn list(&self) -> Vec<&RegisteredExtension> {
        self.extensions.values().collect()
    }
}
