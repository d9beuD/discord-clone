//! Memory-only repository. No platform-specific paths or Apple dependencies.
use chat_core::{Channel, ChatError, ChatRepository, ChatResult, Member, Message, Server};
use std::collections::HashMap;

pub struct MemoryRepository {
    servers: Vec<Server>,
    channels: Vec<Channel>,
    members: HashMap<String, Vec<Member>>,
    messages: HashMap<String, Vec<Message>>,
}

impl MemoryRepository {
    pub fn new(
        servers: Vec<Server>,
        channels: Vec<Channel>,
        members: Vec<(String, Vec<Member>)>,
        messages: Vec<Message>,
    ) -> ChatResult<Self> {
        let mut repository = Self {
            servers,
            channels,
            members: members.into_iter().collect(),
            messages: HashMap::new(),
        };
        for message in messages {
            repository.insert_message(message)?;
        }
        Ok(repository)
    }

    fn require_channel(&self, id: &str) -> ChatResult<()> {
        if self.channels.iter().any(|channel| channel.id == id) {
            Ok(())
        } else {
            Err(ChatError::UnknownIdentifier { id: id.into() })
        }
    }
}

impl ChatRepository for MemoryRepository {
    fn servers(&self) -> Vec<Server> {
        self.servers.clone()
    }

    fn channels(&self, server_id: &str) -> ChatResult<Vec<Channel>> {
        if !self.servers.iter().any(|server| server.id == server_id) {
            return Err(ChatError::UnknownIdentifier {
                id: server_id.into(),
            });
        }
        Ok(self
            .channels
            .iter()
            .filter(|channel| channel.server_id == server_id)
            .cloned()
            .collect())
    }

    fn messages(&self, channel_id: &str) -> ChatResult<Vec<Message>> {
        self.require_channel(channel_id)?;
        Ok(self.messages.get(channel_id).cloned().unwrap_or_default())
    }

    fn members(&self, channel_id: &str) -> ChatResult<Vec<Member>> {
        self.require_channel(channel_id)?;
        Ok(self.members.get(channel_id).cloned().unwrap_or_default())
    }

    fn insert_message(&mut self, message: Message) -> ChatResult<()> {
        self.require_channel(&message.channel_id)?;
        let messages = self.messages.entry(message.channel_id.clone()).or_default();
        if let Some(existing) = messages
            .iter_mut()
            .find(|existing| existing.id == message.id)
        {
            *existing = message;
        } else {
            messages.push(message);
        }
        Ok(())
    }

    fn remove_message(&mut self, channel_id: &str, message_id: &str) -> ChatResult<()> {
        self.require_channel(channel_id)?;
        let messages = self.messages.entry(channel_id.into()).or_default();
        let index = messages
            .iter()
            .position(|message| message.id == message_id)
            .ok_or_else(|| ChatError::UnknownIdentifier {
                id: message_id.into(),
            })?;
        messages.remove(index);
        Ok(())
    }
}
