#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Interchange {
    pub interchange_id: String,
    pub parent_interchange_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InterchangeChain {
    pub interchange_ids: Vec<String>,
}

impl InterchangeChain {
    pub fn root(root_interchange_id: String) -> Self {
        Self {
            interchange_ids: vec![root_interchange_id],
        }
    }

    pub fn current_interchange_id(&self) -> Option<&String> {
        self.interchange_ids.last()
    }

    pub fn create_child(&self, child_interchange_id: String) -> Self {
        let mut next = self.interchange_ids.clone();
        next.push(child_interchange_id);
        Self { interchange_ids: next }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XmipMessage {
    pub message_id: String,
    pub interchange_chain: InterchangeChain,
    pub sections: Vec<XmipSection>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XmipSection {
    pub section_id: String,
    pub stream_reference: String,
}

impl XmipMessage {
    pub fn create_child_message(
        &self,
        new_message_id: String,
        child_interchange_id: String,
        sections: Vec<XmipSection>,
    ) -> Self {
        Self {
            message_id: new_message_id,
            interchange_chain: self.interchange_chain.create_child(child_interchange_id),
            sections,
        }
    }
}
