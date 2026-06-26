use crate::send::location::SendLocation;
use crate::xmip_message_model::PromotedProperty;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendPort {
    pub name: String,
    pub locations: Vec<SendLocation>,
    pub promotions: Vec<PromotedProperty>,
    pub transform_content_type: Option<String>,
}

impl SendPort {
    pub fn new(name: impl Into<String>, locations: Vec<SendLocation>) -> Result<Self, String> {
        if locations.is_empty() {
            return Err("send port requires at least one send location".to_string());
        }

        Ok(Self {
            name: name.into(),
            locations,
            promotions: Vec::new(),
            transform_content_type: None,
        })
    }

    pub fn with_promotion(mut self, property: PromotedProperty) -> Self {
        self.promotions.push(property);
        self
    }

    pub fn with_transform(mut self, content_type: impl Into<String>) -> Self {
        self.transform_content_type = Some(content_type.into());
        self
    }
}
