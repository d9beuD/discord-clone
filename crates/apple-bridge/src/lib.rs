//! Swift-facing adapter. The domain and its infrastructure never depend on this crate.
use chat_core as domain;
use std::sync::Arc;

uniffi::setup_scaffolding!();

#[derive(Debug, Clone, uniffi::Record)]
pub struct Server {
    pub id: String,
    pub name: String,
    pub initials: String,
    pub description: String,
}
#[derive(Debug, Clone, uniffi::Record)]
pub struct Channel {
    pub id: String,
    pub server_id: String,
    pub name: String,
    pub topic: String,
}
#[derive(Debug, Clone, uniffi::Record)]
pub struct User {
    pub id: String,
    pub display_name: String,
    pub initials: String,
    pub bio: String,
}
#[derive(Debug, Clone, uniffi::Record)]
pub struct Member {
    pub user: User,
    pub role: String,
    pub online: bool,
}
#[derive(Debug, Clone, uniffi::Record)]
pub struct Message {
    pub id: String,
    pub channel_id: String,
    pub author: User,
    pub content: String,
    pub created_at_ms: u64,
}
#[derive(Debug, Clone, uniffi::Enum)]
pub enum ChatEvent {
    MessageReceived {
        message: Message,
    },
    MessageDeleted {
        channel_id: String,
        message_id: String,
    },
    UserTyping {
        channel_id: String,
        user_id: String,
    },
}
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum ChatError {
    #[error("Unknown identifier: {id}")]
    UnknownIdentifier { id: String },
    #[error("Message content cannot be empty")]
    EmptyContent,
    #[error("You can only delete your own messages")]
    DeletionForbidden,
    #[error("The session is closed")]
    SessionClosed,
    #[error("Internal failure: {reason}")]
    Internal { reason: String },
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum EventDeliveryError {
    #[error("Event delivery failed: {reason}")]
    Failed { reason: String },
}

impl From<uniffi::UnexpectedUniFFICallbackError> for EventDeliveryError {
    fn from(error: uniffi::UnexpectedUniFFICallbackError) -> Self {
        Self::Failed {
            reason: error.to_string(),
        }
    }
}

#[uniffi::export(foreign)]
pub trait ChatEventListener: Send + Sync + std::fmt::Debug {
    fn on_event(&self, event: ChatEvent) -> Result<(), EventDeliveryError>;
}

struct ListenerAdapter(Arc<dyn ChatEventListener>);
impl domain::EventListener for ListenerAdapter {
    fn on_event(&self, event: domain::ChatEvent) {
        // A finished UI subscription does not invalidate an already committed message.
        let _ = self.0.on_event(event.into());
    }
}

#[derive(uniffi::Object)]
pub struct ChatClient {
    service: domain::ChatService,
}

#[uniffi::export]
impl ChatClient {
    #[uniffi::constructor]
    pub fn new_demo() -> Result<Arc<Self>, ChatError> {
        let snapshot = chat_networking::demo_snapshot();
        let repository = chat_storage::MemoryRepository::new(
            snapshot.servers,
            snapshot.channels,
            snapshot.members,
            snapshot.messages,
        )?;
        let service = domain::ChatService::new(Box::new(repository), snapshot.current_user)?;
        Ok(Arc::new(Self { service }))
    }

    pub fn current_user(&self) -> Result<User, ChatError> {
        Ok(self.service.current_user()?.into())
    }
    pub fn list_servers(&self) -> Result<Vec<Server>, ChatError> {
        Ok(self
            .service
            .servers()?
            .into_iter()
            .map(Into::into)
            .collect())
    }
    pub fn list_channels(&self, server_id: String) -> Result<Vec<Channel>, ChatError> {
        Ok(self
            .service
            .channels(&server_id)?
            .into_iter()
            .map(Into::into)
            .collect())
    }
    pub fn list_messages(&self, channel_id: String) -> Result<Vec<Message>, ChatError> {
        Ok(self
            .service
            .messages(&channel_id)?
            .into_iter()
            .map(Into::into)
            .collect())
    }
    pub fn list_members(&self, channel_id: String) -> Result<Vec<Member>, ChatError> {
        Ok(self
            .service
            .members(&channel_id)?
            .into_iter()
            .map(Into::into)
            .collect())
    }
    pub fn send_message(&self, channel_id: String, content: String) -> Result<Message, ChatError> {
        Ok(self.service.send_message(&channel_id, &content)?.into())
    }
    pub fn delete_message(&self, channel_id: String, message_id: String) -> Result<(), ChatError> {
        Ok(self.service.delete_message(&channel_id, &message_id)?)
    }
    pub fn set_event_listener(
        &self,
        listener: Arc<dyn ChatEventListener>,
    ) -> Result<(), ChatError> {
        Ok(self
            .service
            .set_listener(Arc::new(ListenerAdapter(listener)))?)
    }
    pub fn clear_event_listener(&self) -> Result<(), ChatError> {
        Ok(self.service.clear_listener()?)
    }
    pub fn close(&self) {
        self.service.close();
    }
}

macro_rules! convert_record {
    ($name:ident { $($field:ident),* $(,)? }) => {
        impl From<domain::$name> for $name {
            fn from(value: domain::$name) -> Self {
                Self { $($field: value.$field.into()),* }
            }
        }
    };
}
convert_record!(Server {
    id,
    name,
    initials,
    description
});
convert_record!(Channel {
    id,
    server_id,
    name,
    topic
});
convert_record!(User {
    id,
    display_name,
    initials,
    bio
});
convert_record!(Member { user, role, online });
convert_record!(Message {
    id,
    channel_id,
    author,
    content,
    created_at_ms
});

impl From<domain::ChatEvent> for ChatEvent {
    fn from(event: domain::ChatEvent) -> Self {
        match event {
            domain::ChatEvent::MessageReceived { message } => Self::MessageReceived {
                message: message.into(),
            },
            domain::ChatEvent::MessageDeleted {
                channel_id,
                message_id,
            } => Self::MessageDeleted {
                channel_id,
                message_id,
            },
            domain::ChatEvent::UserTyping {
                channel_id,
                user_id,
            } => Self::UserTyping {
                channel_id,
                user_id,
            },
        }
    }
}
impl From<domain::ChatError> for ChatError {
    fn from(error: domain::ChatError) -> Self {
        match error {
            domain::ChatError::UnknownIdentifier { id } => Self::UnknownIdentifier { id },
            domain::ChatError::EmptyContent => Self::EmptyContent,
            domain::ChatError::DeletionForbidden => Self::DeletionForbidden,
            domain::ChatError::SessionClosed => Self::SessionClosed,
            domain::ChatError::Internal { reason } => Self::Internal { reason },
        }
    }
}
