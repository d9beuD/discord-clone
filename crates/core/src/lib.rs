//! Platform-independent domain, storage contract and session service.

use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::runtime::{Builder, Runtime};
use tokio::sync::mpsc;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Server {
    pub id: String,
    pub name: String,
    pub initials: String,
    pub description: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Channel {
    pub id: String,
    pub server_id: String,
    pub name: String,
    pub topic: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct User {
    pub id: String,
    pub display_name: String,
    pub initials: String,
    pub bio: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Member {
    pub user: User,
    pub role: String,
    pub online: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Message {
    pub id: String,
    pub channel_id: String,
    pub author: User,
    pub content: String,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
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

#[derive(Debug, thiserror::Error, Clone, PartialEq, Eq)]
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

pub type ChatResult<T> = Result<T, ChatError>;

/// Implemented by memory storage today; SQLite can implement the same contract.
pub trait ChatRepository: Send {
    fn servers(&self) -> Vec<Server>;
    fn channels(&self, server_id: &str) -> ChatResult<Vec<Channel>>;
    fn messages(&self, channel_id: &str) -> ChatResult<Vec<Message>>;
    fn members(&self, channel_id: &str) -> ChatResult<Vec<Member>>;
    fn insert_message(&mut self, message: Message) -> ChatResult<()>;
    fn remove_message(&mut self, channel_id: &str, message_id: &str) -> ChatResult<()>;
}

pub trait EventListener: Send + Sync {
    fn on_event(&self, event: ChatEvent);
}

#[derive(Default)]
struct ListenerSlot {
    generation: u64,
    listener: Option<Arc<dyn EventListener>>,
}

struct QueuedEvent {
    generation: u64,
    event: ChatEvent,
}

struct State {
    repository: Box<dyn ChatRepository>,
    sender: Option<mpsc::UnboundedSender<QueuedEvent>>,
    runtime: Option<Runtime>,
    next_message: u64,
    closed: bool,
}

pub struct ChatService {
    state: Mutex<State>,
    listener: Arc<Mutex<ListenerSlot>>,
    current_user: User,
}

impl ChatService {
    pub fn new(repository: Box<dyn ChatRepository>, current_user: User) -> ChatResult<Self> {
        let runtime = Builder::new_multi_thread()
            .worker_threads(1)
            .thread_name("chat-events")
            .build()
            .map_err(|error| ChatError::Internal {
                reason: error.to_string(),
            })?;
        let (sender, mut receiver) = mpsc::unbounded_channel::<QueuedEvent>();
        let listener = Arc::new(Mutex::new(ListenerSlot::default()));
        let dispatch_listener = Arc::clone(&listener);
        runtime.spawn(async move {
            while let Some(queued) = receiver.recv().await {
                let callback = dispatch_listener.lock().ok().and_then(|slot| {
                    (slot.generation == queued.generation)
                        .then(|| slot.listener.clone())
                        .flatten()
                });
                // Foreign code may re-enter the service: release every lock first.
                if let Some(callback) = callback {
                    callback.on_event(queued.event);
                }
            }
        });
        Ok(Self {
            state: Mutex::new(State {
                repository,
                sender: Some(sender),
                runtime: Some(runtime),
                next_message: 1,
                closed: false,
            }),
            listener,
            current_user,
        })
    }

    fn state(&self) -> ChatResult<MutexGuard<'_, State>> {
        let state = self.state.lock().map_err(|_| ChatError::Internal {
            reason: "Session lock poisoned".into(),
        })?;
        if state.closed {
            return Err(ChatError::SessionClosed);
        }
        Ok(state)
    }

    pub fn current_user(&self) -> ChatResult<User> {
        let _state = self.state()?;
        Ok(self.current_user.clone())
    }

    pub fn servers(&self) -> ChatResult<Vec<Server>> {
        Ok(self.state()?.repository.servers())
    }

    pub fn channels(&self, server_id: &str) -> ChatResult<Vec<Channel>> {
        self.state()?.repository.channels(server_id)
    }

    pub fn messages(&self, channel_id: &str) -> ChatResult<Vec<Message>> {
        self.state()?.repository.messages(channel_id)
    }

    pub fn members(&self, channel_id: &str) -> ChatResult<Vec<Member>> {
        self.state()?.repository.members(channel_id)
    }

    pub fn set_listener(&self, listener: Arc<dyn EventListener>) -> ChatResult<()> {
        let _state = self.state()?;
        let mut slot = self.listener.lock().map_err(|_| ChatError::Internal {
            reason: "Listener lock poisoned".into(),
        })?;
        slot.generation += 1;
        slot.listener = Some(listener);
        Ok(())
    }

    pub fn clear_listener(&self) -> ChatResult<()> {
        let _state = self.state()?;
        self.invalidate_listener();
        Ok(())
    }

    fn invalidate_listener(&self) {
        if let Ok(mut slot) = self.listener.lock() {
            slot.generation += 1;
            slot.listener = None;
        }
    }

    fn publish(&self, state: &State, event: ChatEvent) -> ChatResult<()> {
        let slot = self.listener.lock().map_err(|_| ChatError::Internal {
            reason: "Listener lock poisoned".into(),
        })?;
        if slot.listener.is_some() {
            state
                .sender
                .as_ref()
                .ok_or(ChatError::SessionClosed)?
                .send(QueuedEvent {
                    generation: slot.generation,
                    event,
                })
                .map_err(|_| ChatError::SessionClosed)?;
        }
        Ok(())
    }

    pub fn send_message(&self, channel_id: &str, content: &str) -> ChatResult<Message> {
        let mut state = self.state()?;
        if content.trim().is_empty() {
            return Err(ChatError::EmptyContent);
        }
        state.repository.messages(channel_id)?;
        let created_at_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|error| ChatError::Internal {
                reason: error.to_string(),
            })?
            .as_millis() as u64;
        let message = Message {
            id: format!("local-{}", state.next_message),
            channel_id: channel_id.into(),
            author: self.current_user.clone(),
            content: content.into(),
            created_at_ms,
        };
        state.next_message += 1;
        state.repository.insert_message(message.clone())?;
        self.publish(
            &state,
            ChatEvent::MessageReceived {
                message: message.clone(),
            },
        )?;
        Ok(message)
    }

    pub fn delete_message(&self, channel_id: &str, message_id: &str) -> ChatResult<()> {
        let mut state = self.state()?;
        let message = state
            .repository
            .messages(channel_id)?
            .into_iter()
            .find(|message| message.id == message_id)
            .ok_or_else(|| ChatError::UnknownIdentifier {
                id: message_id.into(),
            })?;
        if message.author.id != self.current_user.id {
            return Err(ChatError::DeletionForbidden);
        }
        state.repository.remove_message(channel_id, message_id)?;
        self.publish(
            &state,
            ChatEvent::MessageDeleted {
                channel_id: channel_id.into(),
                message_id: message_id.into(),
            },
        )
    }

    /// Idempotent. A callback already in flight may finish; adapters cancel their stream first.
    pub fn close(&self) {
        let runtime = if let Ok(mut state) = self.state.lock() {
            state.closed = true;
            self.invalidate_listener();
            state.sender.take();
            state.runtime.take()
        } else {
            None
        };
        if let Some(runtime) = runtime {
            runtime.shutdown_background();
        }
    }
}

impl Drop for ChatService {
    fn drop(&mut self) {
        self.close();
    }
}
