//! Portable models and validation for the published community API.
use crate::{Channel, Member, Server, User};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct UserProfile {
    pub id: String,
    pub username: String,
    pub email: String,
    pub created_at: String,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Guild {
    pub id: String,
    pub name: String,
    pub owner_id: String,
    pub created_at: String,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct BackendChannel {
    pub id: String,
    pub guild_id: String,
    pub kind: ChannelKind,
    pub name: String,
    pub position: i32,
    pub created_at: String,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ChannelKind {
    Text,
    Voice,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct GuildMember {
    pub user_id: String,
    pub username: String,
    pub joined_at: String,
    pub role_ids: Vec<String>,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Role {
    pub id: String,
    pub guild_id: String,
    pub name: String,
    pub permissions: i64,
    pub is_default: bool,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Invite {
    pub id: String,
    pub guild_id: String,
    pub creator_id: String,
    pub created_at: String,
    pub expires_at: Option<String>,
    pub max_uses: Option<i64>,
    pub uses: i64,
    pub revoked_at: Option<String>,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct CreatedInvite {
    pub invite: Invite,
    pub token: String,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ChannelOverride {
    pub id: String,
    pub channel_id: String,
    pub member_id: Option<String>,
    pub role_id: Option<String>,
    pub allow_permissions: i64,
    pub deny_permissions: i64,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ChannelPermissions {
    pub channel_id: String,
    pub permissions: i64,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct HealthResponse {
    pub status: String,
}

pub const ALL_PERMISSIONS: i64 = 127;
pub const MANAGE_CHANNELS: i64 = 8;
pub const MANAGE_ROLES: i64 = 16;
pub const KICK_MEMBERS: i64 = 32;

pub fn validate_name(name: &str) -> Result<&str, &'static str> {
    let name = name.trim();
    if name.is_empty() || name.chars().count() > 100 || name.chars().any(char::is_control) {
        Err("Le nom doit contenir 1 à 100 caractères sans caractères de contrôle.")
    } else {
        Ok(name)
    }
}
pub fn validate_permissions(value: i64) -> Result<(), &'static str> {
    if (0..=ALL_PERMISSIONS).contains(&value) {
        Ok(())
    } else {
        Err("Le masque de permissions doit être compris entre 0 et 127.")
    }
}
pub fn guild_permissions(
    guild: &Guild,
    user_id: &str,
    members: &[GuildMember],
    roles: &[Role],
) -> i64 {
    if guild.owner_id == user_id {
        return ALL_PERMISSIONS;
    }
    let Some(member) = members.iter().find(|member| member.user_id == user_id) else {
        return 0;
    };
    roles
        .iter()
        .filter(|role| role.is_default || member.role_ids.contains(&role.id))
        .fold(0, |mask, role| mask | role.permissions)
}
fn initials(name: &str) -> String {
    name.split_whitespace()
        .take(2)
        .filter_map(|word| word.chars().next())
        .flat_map(char::to_uppercase)
        .collect()
}
impl UserProfile {
    pub fn user(&self) -> User {
        User {
            id: self.id.clone(),
            display_name: self.username.clone(),
            initials: initials(&self.username),
            bio: String::new(),
        }
    }
}
impl Guild {
    pub fn server(&self) -> Server {
        Server {
            id: self.id.clone(),
            name: self.name.clone(),
            initials: initials(&self.name),
            description: String::new(),
        }
    }
}
impl BackendChannel {
    pub fn channel(&self) -> Channel {
        Channel {
            id: self.id.clone(),
            server_id: self.guild_id.clone(),
            name: self.name.clone(),
            topic: match self.kind {
                ChannelKind::Text => "Salon texte",
                ChannelKind::Voice => "Salon vocal",
            }
            .into(),
        }
    }
}
impl GuildMember {
    pub fn member(&self, roles: &[Role]) -> Member {
        Member {
            user: User {
                id: self.user_id.clone(),
                display_name: self.username.clone(),
                initials: initials(&self.username),
                bio: String::new(),
            },
            role: {
                let names = roles
                    .iter()
                    .filter(|role| !role.is_default && self.role_ids.contains(&role.id))
                    .map(|role| role.name.as_str())
                    .collect::<Vec<_>>()
                    .join(", ");
                if names.is_empty() {
                    "Membre".into()
                } else {
                    names
                }
            },
            // shortcut: REST has no presence, display members without an online/offline claim.
            online: false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn names_and_masks_follow_the_backend_contract() {
        assert_eq!(validate_name("  Café 🦀  "), Ok("Café 🦀"));
        for name in ["", "  ", "a\nb", &"é".repeat(101)] {
            assert!(validate_name(name).is_err());
        }
        assert!(validate_name(&"é".repeat(100)).is_ok());
        for mask in [-1, 128, i64::MAX] {
            assert!(validate_permissions(mask).is_err());
        }
        assert!(validate_permissions(127).is_ok());
    }
    #[test]
    fn permissions_include_default_and_assigned_roles_but_not_other_members() {
        let guild = Guild {
            id: "g".into(),
            name: "G".into(),
            owner_id: "owner".into(),
            created_at: "".into(),
        };
        let roles = vec![
            Role {
                id: "default".into(),
                guild_id: "g".into(),
                name: "@everyone".into(),
                permissions: 3,
                is_default: true,
            },
            Role {
                id: "manager".into(),
                guild_id: "g".into(),
                name: "Manager".into(),
                permissions: 8,
                is_default: false,
            },
        ];
        let members = vec![GuildMember {
            user_id: "member".into(),
            username: "M".into(),
            joined_at: "".into(),
            role_ids: vec!["manager".into()],
        }];
        assert_eq!(guild_permissions(&guild, "owner", &members, &roles), 127);
        assert_eq!(guild_permissions(&guild, "member", &members, &roles), 11);
        assert_eq!(guild_permissions(&guild, "absent", &members, &roles), 0);
        assert_eq!(members[0].member(&roles).role, "Manager");
        assert_eq!(members[0].member(&[]).role, "Membre");
    }
}
