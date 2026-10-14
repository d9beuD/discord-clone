//! Deterministic demo source. Real HTTP/WebSocket transport awaits the backend contract.
use chat_core::{Channel, Member, Message, Server, User};

pub struct DemoSnapshot {
    pub current_user: User,
    pub servers: Vec<Server>,
    pub channels: Vec<Channel>,
    pub members: Vec<(String, Vec<Member>)>,
    pub messages: Vec<Message>,
}

pub fn demo_snapshot() -> DemoSnapshot {
    let me = user(
        "you",
        "Camille",
        "CA",
        "Design, code et conversations. Profil de démonstration.",
    );
    let alex = user(
        "alex",
        "Alex Morgan",
        "AM",
        "Je construis des choses simples, ensemble.",
    );
    let lea = user(
        "lea",
        "Léa Martin",
        "LM",
        "Interfaces natives et détails qui comptent.",
    );
    let sam = user("sam", "Sam Rivera", "SR", "Rust, musique et café.");
    let servers = vec![
        server(
            "atelier",
            "L’Atelier",
            "AT",
            "Un espace pour créer et échanger.",
        ),
        server(
            "rust",
            "Rust & Friends",
            "RF",
            "Des idées, du code et de l’entraide.",
        ),
        server("cafe", "Café du coin", "CC", "La pause entre deux projets."),
    ];
    let channels = vec![
        channel(
            "general",
            "atelier",
            "général",
            "Les nouvelles de l’atelier et les discussions du quotidien.",
        ),
        channel(
            "design",
            "atelier",
            "design",
            "Interfaces, inspirations et petits détails.",
        ),
        channel(
            "ideas",
            "atelier",
            "idées",
            "Un espace encore vide pour votre prochaine idée.",
        ),
        channel(
            "rust-general",
            "rust",
            "discussion",
            "Rust, sans prise de tête.",
        ),
        channel(
            "help",
            "rust",
            "entraide",
            "Posez votre prochaine question.",
        ),
        channel(
            "coffee",
            "cafe",
            "pause-café",
            "Prenez le temps de discuter.",
        ),
    ];
    let people = vec![
        Member {
            user: me.clone(),
            role: "Membre".into(),
            online: true,
        },
        Member {
            user: alex.clone(),
            role: "Administrateur".into(),
            online: true,
        },
        Member {
            user: lea.clone(),
            role: "Membre".into(),
            online: true,
        },
        Member {
            user: sam.clone(),
            role: "Membre".into(),
            online: false,
        },
    ];
    let members = channels
        .iter()
        .map(|channel| (channel.id.clone(), people.clone()))
        .collect();
    let messages = vec![
        message(
            "seed-1",
            "general",
            &alex,
            "Bienvenue dans L’Atelier 👋\nUn petit espace pour partager ce qu’on construit.",
            1_791_964_800_000,
        ),
        message(
            "seed-2",
            "general",
            &lea,
            "J’aime beaucoup cette idée. On commence par une interface qui se sent vraiment chez elle sur Mac ?",
            1_791_965_100_000,
        ),
        message(
            "seed-3",
            "general",
            &me,
            "Oui ! Navigation native, cœur Rust et quelques conversations pour prendre nos repères.",
            1_791_965_280_000,
        ),
        message(
            "seed-4",
            "general",
            &sam,
            "Le mode démo garde tout en mémoire. Le backend viendra ensuite 🦀",
            1_791_965_460_000,
        ),
        message(
            "seed-5",
            "design",
            &lea,
            "Du rythme, de l’espace et une typographie système.\nLes détails font le reste.",
            1_791_965_600_000,
        ),
        message(
            "seed-6",
            "rust-general",
            &sam,
            "Les modèles et la logique restent indépendants de l’interface. Un bon départ pour plusieurs plateformes.",
            1_791_965_900_000,
        ),
        message(
            "seed-7",
            "coffee",
            &alex,
            "Quelqu’un pour un café ? ☕",
            1_791_966_000_000,
        ),
    ];
    DemoSnapshot {
        current_user: me,
        servers,
        channels,
        members,
        messages,
    }
}

fn user(id: &str, name: &str, initials: &str, bio: &str) -> User {
    User {
        id: id.into(),
        display_name: name.into(),
        initials: initials.into(),
        bio: bio.into(),
    }
}
fn server(id: &str, name: &str, initials: &str, description: &str) -> Server {
    Server {
        id: id.into(),
        name: name.into(),
        initials: initials.into(),
        description: description.into(),
    }
}
fn channel(id: &str, server_id: &str, name: &str, topic: &str) -> Channel {
    Channel {
        id: id.into(),
        server_id: server_id.into(),
        name: name.into(),
        topic: topic.into(),
    }
}
fn message(
    id: &str,
    channel_id: &str,
    author: &User,
    content: &str,
    created_at_ms: u64,
) -> Message {
    Message {
        id: id.into(),
        channel_id: channel_id.into(),
        author: author.clone(),
        content: content.into(),
        created_at_ms,
    }
}
