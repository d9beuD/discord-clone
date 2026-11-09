//! UniFFI mapping only; networking and community rules live in portable Rust.
use crate::{Channel, Member, Server, User};
use chat_core::community as model;
use chat_networking::backend::{BackendError as Error, BackendSession};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum ChannelKind {
    Text,
    Voice,
}
impl From<model::ChannelKind> for ChannelKind {
    fn from(value: model::ChannelKind) -> Self {
        match value {
            model::ChannelKind::Text => Self::Text,
            model::ChannelKind::Voice => Self::Voice,
        }
    }
}
impl From<ChannelKind> for model::ChannelKind {
    fn from(value: ChannelKind) -> Self {
        match value {
            ChannelKind::Text => Self::Text,
            ChannelKind::Voice => Self::Voice,
        }
    }
}
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum BackendError {
    #[error("{detail}")]
    InvalidInput { detail: String },
    #[error("{detail}")]
    Http { status: u16, detail: String },
    #[error("Le serveur est inaccessible.")]
    Transport,
    #[error("La réponse du serveur est invalide.")]
    InvalidResponse,
    #[error("La session est fermée.")]
    SessionClosed,
}
impl From<Error> for BackendError {
    fn from(error: Error) -> Self {
        match error {
            Error::InvalidInput { detail } => Self::InvalidInput { detail },
            Error::Http { status, detail } => Self::Http { status, detail },
            Error::Transport => Self::Transport,
            Error::InvalidResponse => Self::InvalidResponse,
            Error::SessionClosed => Self::SessionClosed,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct AccountProfile {
    pub id: String,
    pub username: String,
    pub email: String,
    pub created_at: String,
}
impl From<model::UserProfile> for AccountProfile {
    fn from(value: model::UserProfile) -> Self {
        Self {
            id: value.id,
            username: value.username,
            email: value.email,
            created_at: value.created_at,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct Guild {
    pub id: String,
    pub name: String,
    pub owner_id: String,
    pub created_at: String,
}
impl From<model::Guild> for Guild {
    fn from(value: model::Guild) -> Self {
        Self {
            id: value.id,
            name: value.name,
            owner_id: value.owner_id,
            created_at: value.created_at,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct RemoteChannel {
    pub id: String,
    pub guild_id: String,
    pub kind: ChannelKind,
    pub name: String,
    pub position: i32,
    pub created_at: String,
}
impl From<model::BackendChannel> for RemoteChannel {
    fn from(value: model::BackendChannel) -> Self {
        Self {
            id: value.id,
            guild_id: value.guild_id,
            kind: value.kind.into(),
            name: value.name,
            position: value.position,
            created_at: value.created_at,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct GuildMember {
    pub user_id: String,
    pub username: String,
    pub joined_at: String,
    pub role_ids: Vec<String>,
}
impl From<model::GuildMember> for GuildMember {
    fn from(value: model::GuildMember) -> Self {
        Self {
            user_id: value.user_id,
            username: value.username,
            joined_at: value.joined_at,
            role_ids: value.role_ids,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct Role {
    pub id: String,
    pub guild_id: String,
    pub name: String,
    pub permissions: i64,
    pub is_default: bool,
}
impl From<model::Role> for Role {
    fn from(value: model::Role) -> Self {
        Self {
            id: value.id,
            guild_id: value.guild_id,
            name: value.name,
            permissions: value.permissions,
            is_default: value.is_default,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
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
impl From<model::Invite> for Invite {
    fn from(value: model::Invite) -> Self {
        Self {
            id: value.id,
            guild_id: value.guild_id,
            creator_id: value.creator_id,
            created_at: value.created_at,
            expires_at: value.expires_at,
            max_uses: value.max_uses,
            uses: value.uses,
            revoked_at: value.revoked_at,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct CreatedInvite {
    pub invite: Invite,
    pub token: String,
}
impl From<model::CreatedInvite> for CreatedInvite {
    fn from(value: model::CreatedInvite) -> Self {
        Self {
            invite: value.invite.into(),
            token: value.token,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct ChannelOverride {
    pub id: String,
    pub channel_id: String,
    pub member_id: Option<String>,
    pub role_id: Option<String>,
    pub allow_permissions: i64,
    pub deny_permissions: i64,
}
impl From<model::ChannelOverride> for ChannelOverride {
    fn from(value: model::ChannelOverride) -> Self {
        Self {
            id: value.id,
            channel_id: value.channel_id,
            member_id: value.member_id,
            role_id: value.role_id,
            allow_permissions: value.allow_permissions,
            deny_permissions: value.deny_permissions,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct ChannelAccess {
    pub channel_id: String,
    pub permissions: i64,
    pub can_manage_channels: bool,
    pub can_manage_roles: bool,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct BackendWorkspace {
    pub guild: Guild,
    pub channels: Vec<Channel>,
    pub remote_channels: Vec<RemoteChannel>,
    pub members: Vec<Member>,
    pub guild_members: Vec<GuildMember>,
    pub roles: Vec<Role>,
    pub can_manage_channels: bool,
    pub can_manage_roles: bool,
    pub can_kick_members: bool,
    pub is_owner: bool,
}

#[derive(uniffi::Object)]
pub struct BackendClient {
    session: BackendSession,
}
#[uniffi::export]
impl BackendClient {
    #[uniffi::constructor]
    pub fn login(
        base_url: String,
        email: String,
        password: String,
    ) -> Result<Arc<Self>, BackendError> {
        Ok(Arc::new(Self {
            session: BackendSession::authenticate(&base_url, &email, &password, None)?,
        }))
    }
    #[uniffi::constructor]
    pub fn register(
        base_url: String,
        username: String,
        email: String,
        password: String,
    ) -> Result<Arc<Self>, BackendError> {
        Ok(Arc::new(Self {
            session: BackendSession::authenticate(&base_url, &email, &password, Some(&username))?,
        }))
    }
    pub fn current_user(&self) -> User {
        self.session.user.user().into()
    }
    pub fn expires_at(&self) -> String {
        self.session.expires_at.clone()
    }
    pub fn profile(&self) -> Result<AccountProfile, BackendError> {
        Ok(self.session.profile()?.into())
    }
    pub fn list_servers(&self) -> Result<Vec<Server>, BackendError> {
        Ok(self
            .session
            .guilds()?
            .into_iter()
            .map(|guild| guild.server().into())
            .collect())
    }
    pub fn workspace(&self, guild_id: String) -> Result<BackendWorkspace, BackendError> {
        let workspace = self.session.community(&guild_id)?;
        Ok(BackendWorkspace {
            is_owner: workspace.guild.owner_id == self.session.user.id,
            can_manage_channels: workspace.permissions & model::MANAGE_CHANNELS != 0,
            can_manage_roles: workspace.permissions & model::MANAGE_ROLES != 0,
            can_kick_members: workspace.permissions & model::KICK_MEMBERS != 0,
            channels: workspace
                .channels
                .iter()
                .map(|channel| channel.channel().into())
                .collect(),
            remote_channels: workspace.channels.into_iter().map(Into::into).collect(),
            members: workspace
                .members
                .iter()
                .map(|member| member.member(&workspace.roles).into())
                .collect(),
            guild_members: workspace.members.into_iter().map(Into::into).collect(),
            roles: workspace.roles.into_iter().map(Into::into).collect(),
            guild: workspace.guild.into(),
        })
    }
    pub fn channel(&self, channel_id: String) -> Result<RemoteChannel, BackendError> {
        Ok(self.session.channel(&channel_id)?.into())
    }
    pub fn channel_access(&self, channel_id: String) -> Result<ChannelAccess, BackendError> {
        let access = self.session.channel_permissions(&channel_id)?;
        Ok(ChannelAccess {
            channel_id: access.channel_id,
            permissions: access.permissions,
            can_manage_channels: access.permissions & model::MANAGE_CHANNELS != 0,
            can_manage_roles: access.permissions & model::MANAGE_ROLES != 0,
        })
    }
    pub fn create_guild(&self, name: String) -> Result<Guild, BackendError> {
        Ok(self.session.create_guild(&name)?.into())
    }
    pub fn rename_guild(&self, guild_id: String, name: String) -> Result<Guild, BackendError> {
        Ok(self.session.rename_guild(&guild_id, &name)?.into())
    }
    pub fn delete_guild(&self, guild_id: String) -> Result<(), BackendError> {
        Ok(self.session.delete_guild(&guild_id)?)
    }
    pub fn leave_guild(&self, guild_id: String) -> Result<(), BackendError> {
        Ok(self.session.leave_guild(&guild_id)?)
    }
    pub fn create_channel(
        &self,
        guild_id: String,
        name: String,
        kind: ChannelKind,
        position: i32,
    ) -> Result<RemoteChannel, BackendError> {
        Ok(self
            .session
            .create_channel(&guild_id, &name, kind.into(), position)?
            .into())
    }
    pub fn update_channel(
        &self,
        channel_id: String,
        name: String,
        position: i32,
    ) -> Result<RemoteChannel, BackendError> {
        Ok(self
            .session
            .update_channel(&channel_id, &name, position)?
            .into())
    }
    pub fn delete_channel(&self, channel_id: String) -> Result<(), BackendError> {
        Ok(self.session.delete_channel(&channel_id)?)
    }
    pub fn kick_member(&self, guild_id: String, user_id: String) -> Result<(), BackendError> {
        Ok(self.session.kick_member(&guild_id, &user_id)?)
    }
    pub fn create_role(
        &self,
        guild_id: String,
        name: String,
        permissions: i64,
    ) -> Result<Role, BackendError> {
        Ok(self
            .session
            .create_role(&guild_id, &name, permissions)?
            .into())
    }
    pub fn update_role(
        &self,
        guild_id: String,
        role_id: String,
        name: Option<String>,
        permissions: i64,
    ) -> Result<Role, BackendError> {
        Ok(self
            .session
            .update_role(&guild_id, &role_id, name.as_deref(), permissions)?
            .into())
    }
    pub fn delete_role(&self, guild_id: String, role_id: String) -> Result<(), BackendError> {
        Ok(self.session.delete_role(&guild_id, &role_id)?)
    }
    pub fn set_member_role(
        &self,
        guild_id: String,
        user_id: String,
        role_id: String,
        assigned: bool,
    ) -> Result<(), BackendError> {
        Ok(self
            .session
            .set_member_role(&guild_id, &user_id, &role_id, assigned)?)
    }
    pub fn list_invites(&self, guild_id: String) -> Result<Vec<Invite>, BackendError> {
        Ok(self
            .session
            .invites(&guild_id)?
            .into_iter()
            .map(Into::into)
            .collect())
    }
    pub fn create_invite(
        &self,
        guild_id: String,
        expires_in_seconds: Option<i64>,
        max_uses: Option<i64>,
    ) -> Result<CreatedInvite, BackendError> {
        Ok(self
            .session
            .create_invite(&guild_id, expires_in_seconds, max_uses)?
            .into())
    }
    pub fn revoke_invite(&self, guild_id: String, invite_id: String) -> Result<(), BackendError> {
        Ok(self.session.revoke_invite(&guild_id, &invite_id)?)
    }
    pub fn accept_invite(&self, token: String) -> Result<Guild, BackendError> {
        Ok(self.session.accept_invite(&token)?.into())
    }
    pub fn list_overrides(&self, channel_id: String) -> Result<Vec<ChannelOverride>, BackendError> {
        Ok(self
            .session
            .overrides(&channel_id)?
            .into_iter()
            .map(Into::into)
            .collect())
    }
    pub fn put_override(
        &self,
        channel_id: String,
        role_id: Option<String>,
        member_id: Option<String>,
        allow: i64,
        deny: i64,
    ) -> Result<ChannelOverride, BackendError> {
        Ok(self
            .session
            .put_override(
                &channel_id,
                role_id.as_deref(),
                member_id.as_deref(),
                allow,
                deny,
            )?
            .into())
    }
    pub fn delete_override(
        &self,
        channel_id: String,
        override_id: String,
    ) -> Result<(), BackendError> {
        Ok(self.session.delete_override(&channel_id, &override_id)?)
    }
    pub fn logout(&self) -> Result<(), BackendError> {
        Ok(self.session.logout()?)
    }
    pub fn close(&self) {
        self.session.close();
    }
}
#[uniffi::export]
pub fn backend_health(base_url: String, readiness: bool) -> Result<String, BackendError> {
    Ok(BackendSession::health(&base_url, readiness)?.status)
}
