use chat_core::{ChatError, ChatEvent, ChatService, EventListener};
use chat_storage::MemoryRepository;
use std::sync::{Arc, Mutex, Weak, mpsc};
use std::time::Duration;

fn service() -> Arc<ChatService> {
    let data = chat_networking::demo_snapshot();
    let repository =
        MemoryRepository::new(data.servers, data.channels, data.members, data.messages).unwrap();
    Arc::new(ChatService::new(Box::new(repository), data.current_user).unwrap())
}

struct Probe {
    service: Weak<ChatService>,
    sender: Mutex<mpsc::Sender<(ChatEvent, bool)>>,
}
impl EventListener for Probe {
    fn on_event(&self, event: ChatEvent) {
        let service = self.service.upgrade().unwrap();
        let committed = match &event {
            ChatEvent::MessageReceived { message } => service
                .messages(&message.channel_id)
                .unwrap()
                .contains(message),
            ChatEvent::MessageDeleted {
                channel_id,
                message_id,
            } => !service
                .messages(channel_id)
                .unwrap()
                .iter()
                .any(|message| &message.id == message_id),
            ChatEvent::UserTyping { .. } => true,
        };
        self.sender
            .lock()
            .unwrap()
            .send((event, committed))
            .unwrap();
    }
}

#[test]
fn unicode_multiline_and_channel_isolation() {
    let service = service();
    let content = "  Bonjour 🦀\nこんにちは\nDeuxième ligne  ";
    let original = service.messages("general").unwrap();
    let sent = service.send_message("ideas", content).unwrap();
    assert_eq!(sent.content, content);
    assert_eq!(service.messages("ideas").unwrap(), vec![sent.clone()]);
    assert_eq!(service.messages("general").unwrap(), original);
    assert_eq!(
        service.send_message("ideas", " \n\t "),
        Err(ChatError::EmptyContent)
    );
    assert!(matches!(
        service.send_message("missing", "hello"),
        Err(ChatError::UnknownIdentifier { .. })
    ));
    assert!(matches!(
        service.channels("missing"),
        Err(ChatError::UnknownIdentifier { .. })
    ));
    assert!(matches!(
        service.members("missing"),
        Err(ChatError::UnknownIdentifier { .. })
    ));
    service.delete_message("ideas", &sent.id).unwrap();
    assert!(service.messages("ideas").unwrap().is_empty());
}

#[test]
fn deletion_permissions_and_unknown_message() {
    let service = service();
    assert_eq!(
        service.delete_message("general", "seed-1"),
        Err(ChatError::DeletionForbidden)
    );
    assert!(matches!(
        service.delete_message("general", "missing"),
        Err(ChatError::UnknownIdentifier { .. })
    ));
    service.delete_message("general", "seed-3").unwrap();
    assert_eq!(service.messages("general").unwrap().len(), 3);
}

#[test]
fn callbacks_reenter_without_locks_and_observe_committed_storage() {
    let service = service();
    let (sender, receiver) = mpsc::channel();
    service
        .set_listener(Arc::new(Probe {
            service: Arc::downgrade(&service),
            sender: Mutex::new(sender),
        }))
        .unwrap();
    let sent = service.send_message("ideas", "first").unwrap();
    service.delete_message("ideas", &sent.id).unwrap();
    // The deletion can be committed before the first callback, so inspect receipt separately.
    let (event, _) = receiver.recv_timeout(Duration::from_secs(2)).unwrap();
    assert!(matches!(event, ChatEvent::MessageReceived { .. }));
    let (event, committed) = receiver.recv_timeout(Duration::from_secs(2)).unwrap();
    assert!(matches!(event, ChatEvent::MessageDeleted { .. }));
    assert!(committed);
    let sent = service.send_message("ideas", "second").unwrap();
    let (event, committed) = receiver.recv_timeout(Duration::from_secs(2)).unwrap();
    assert_eq!(event, ChatEvent::MessageReceived { message: sent });
    assert!(committed);
    service.clear_listener().unwrap();
    service.send_message("ideas", "no callback").unwrap();
    assert!(receiver.recv_timeout(Duration::from_millis(100)).is_err());
}

#[test]
fn closing_is_idempotent_and_new_sessions_reset_data() {
    let first = service();
    first.send_message("ideas", "ephemeral").unwrap();
    first.close();
    first.close();
    assert_eq!(first.servers(), Err(ChatError::SessionClosed));
    assert_eq!(
        first.send_message("ideas", "closed"),
        Err(ChatError::SessionClosed)
    );
    assert_eq!(first.clear_listener(), Err(ChatError::SessionClosed));
    assert_eq!(first.current_user(), Err(ChatError::SessionClosed));
    assert!(service().messages("ideas").unwrap().is_empty());
}

#[test]
fn concurrent_mutations_have_unique_ids_and_ordered_events() {
    let service = service();
    let (sender, receiver) = mpsc::channel();
    service
        .set_listener(Arc::new(Probe {
            service: Arc::downgrade(&service),
            sender: Mutex::new(sender),
        }))
        .unwrap();
    let workers: Vec<_> = (0..8)
        .map(|index| {
            let service = Arc::clone(&service);
            std::thread::spawn(move || {
                service
                    .send_message("ideas", &format!("message {index}"))
                    .unwrap()
            })
        })
        .collect();
    let mut ids: Vec<_> = workers
        .into_iter()
        .map(|worker| worker.join().unwrap().id)
        .collect();
    ids.sort();
    ids.dedup();
    assert_eq!(ids.len(), 8);
    let messages = service.messages("ideas").unwrap();
    assert_eq!(messages.len(), 8);
    let received: Vec<_> = (0..8)
        .map(|_| {
            let (event, committed) = receiver.recv_timeout(Duration::from_secs(2)).unwrap();
            assert!(committed);
            match event {
                ChatEvent::MessageReceived { message } => message.id,
                _ => panic!("Expected a received message"),
            }
        })
        .collect();
    assert_eq!(
        received,
        messages
            .into_iter()
            .map(|message| message.id)
            .collect::<Vec<_>>()
    );
}
