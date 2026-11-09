//! REST session. All HTTP, credentials, validation and permission decisions stay in Rust.
use chat_core::community::*;
use reqwest::{Method, Url, blocking::Client, redirect::Policy};
use serde::{Deserialize, de::DeserializeOwned};
use serde_json::{Value, json};
use std::{sync::Mutex, time::Duration};

#[derive(Debug, thiserror::Error)]
pub enum BackendError {
    #[error("{detail}")]
    InvalidInput { detail: String },
    #[error("{detail}")]
    Http { status: u16, detail: String },
    #[error("Le serveur est inaccessible. Vérifiez son adresse et votre connexion.")]
    Transport,
    #[error("La réponse du serveur est invalide.")]
    InvalidResponse,
    #[error("La session est fermée. Reconnectez-vous.")]
    SessionClosed,
}
pub type Result<T> = std::result::Result<T, BackendError>;
fn invalid(detail: impl Into<String>) -> BackendError {
    BackendError::InvalidInput {
        detail: detail.into(),
    }
}
fn name(value: &str) -> Result<&str> {
    validate_name(value).map_err(invalid)
}
fn account_name(value: &str) -> Result<&str> {
    let value = value.trim();
    if !(3..=32).contains(&value.len())
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"_-.".contains(&byte))
    {
        return Err(invalid(
            "Le nom de compte doit contenir 3 à 32 lettres ASCII, chiffres, tirets, points ou underscores.",
        ));
    }
    Ok(value)
}
fn mask(value: i64) -> Result<()> {
    validate_permissions(value).map_err(invalid)
}
fn id(value: &str) -> Result<String> {
    uuid::Uuid::parse_str(value)
        .map(|id| id.to_string())
        .map_err(|_| invalid("Identifiant invalide."))
}
#[derive(Deserialize)]
struct AuthResponse {
    user: UserProfile,
    token: String,
    token_type: String,
    expires_at: String,
}
#[derive(Deserialize)]
struct Problem {
    detail: String,
}

pub struct BackendSession {
    http: Client,
    base: Url,
    token: Mutex<Option<String>>,
    pub user: UserProfile,
    pub expires_at: String,
}
pub struct Community {
    pub guild: Guild,
    pub channels: Vec<BackendChannel>,
    pub members: Vec<GuildMember>,
    pub roles: Vec<Role>,
    pub permissions: i64,
}
impl BackendSession {
    fn transport(base_url: &str) -> Result<(Client, Url)> {
        let mut base =
            Url::parse(base_url.trim()).map_err(|_| invalid("Adresse du backend invalide."))?;
        let local = base.host_str().is_some_and(|host| {
            host == "localhost"
                || host
                    .trim_matches(['[', ']'])
                    .parse::<std::net::IpAddr>()
                    .is_ok_and(|ip| ip.is_loopback())
        });
        if !base.username().is_empty()
            || base.password().is_some()
            || base.query().is_some()
            || base.fragment().is_some()
            || !matches!(base.path(), "" | "/")
            || !(base.scheme() == "https" || base.scheme() == "http" && local)
        {
            return Err(invalid(
                "Utilisez une adresse HTTPS, ou HTTP sur localhost, sans chemin ni identifiants.",
            ));
        }
        base.set_path("/");
        let http = Client::builder()
            .timeout(Duration::from_secs(15))
            .connect_timeout(Duration::from_secs(5))
            .redirect(Policy::none())
            .build()
            .map_err(|_| BackendError::Transport)?;
        Ok((http, base))
    }
    pub fn authenticate(
        base_url: &str,
        email: &str,
        password: &str,
        username: Option<&str>,
    ) -> Result<Self> {
        let email = email.trim();
        let length = password.chars().count();
        if email.is_empty() || length == 0 || length > 128 || username.is_some() && length < 15 {
            return Err(invalid(
                "Saisissez un e-mail et un mot de passe (15 à 128 caractères pour créer un compte).",
            ));
        }
        let (http, base) = Self::transport(base_url)?;
        let (path, body) = match username {
            Some(username) => (
                "api/v1/auth/register",
                json!({"username":account_name(username)?,"email":email,"password":password}),
            ),
            None => (
                "api/v1/auth/login",
                json!({"email":email,"password":password}),
            ),
        };
        let response = http
            .post(base.join(path).map_err(|_| BackendError::InvalidResponse)?)
            .json(&body)
            .send()
            .map_err(|_| BackendError::Transport)?;
        let auth: AuthResponse = Self::decode(response)?;
        if auth.token.is_empty()
            || !auth.token.eq(auth.token.trim())
            || auth.token_type != "Bearer"
            || auth.token.chars().any(char::is_control)
        {
            return Err(BackendError::InvalidResponse);
        }
        Ok(Self {
            http,
            base,
            token: Mutex::new(Some(auth.token)),
            user: auth.user,
            expires_at: auth.expires_at,
        })
    }
    fn response_error(response: reqwest::blocking::Response) -> BackendError {
        let status = response.status().as_u16();
        let detail = response
            .json::<Problem>()
            .ok()
            .map(|problem| problem.detail)
            .filter(|detail| !detail.trim().is_empty())
            .unwrap_or_else(|| format!("Le serveur a refusé l’action (HTTP {status})."));
        BackendError::Http { status, detail }
    }
    fn decode<T: DeserializeOwned>(response: reqwest::blocking::Response) -> Result<T> {
        if !response.status().is_success() {
            return Err(Self::response_error(response));
        }
        response.json().map_err(|_| BackendError::InvalidResponse)
    }
    fn request(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<reqwest::blocking::Response> {
        let token = self
            .token
            .lock()
            .map_err(|_| BackendError::SessionClosed)?
            .clone()
            .ok_or(BackendError::SessionClosed)?;
        let mut request = self
            .http
            .request(
                method,
                self.base
                    .join(path)
                    .map_err(|_| BackendError::InvalidResponse)?,
            )
            .bearer_auth(token);
        if let Some(body) = body {
            request = request.json(&body);
        }
        let response = request.send().map_err(|_| BackendError::Transport)?;
        if response.status().as_u16() == 401 {
            self.close();
        }
        if !response.status().is_success() {
            return Err(Self::response_error(response));
        }
        // A close during I/O invalidates even a successful response.
        if self
            .token
            .lock()
            .map_err(|_| BackendError::SessionClosed)?
            .is_none()
        {
            return Err(BackendError::SessionClosed);
        }
        Ok(response)
    }
    fn get<T: DeserializeOwned>(&self, path: &str) -> Result<T> {
        Self::decode(self.request(Method::GET, path, None)?)
    }
    fn write<T: DeserializeOwned>(&self, method: Method, path: &str, body: Value) -> Result<T> {
        Self::decode(self.request(method, path, Some(body))?)
    }
    fn empty(&self, method: Method, path: &str) -> Result<()> {
        self.request(method, path, None).map(|_| ())
    }
    pub fn close(&self) {
        if let Ok(mut token) = self.token.lock() {
            *token = None;
        }
    }
    pub fn logout(&self) -> Result<()> {
        let result = self.empty(Method::POST, "api/v1/auth/logout");
        self.close();
        result
    }
    pub fn profile(&self) -> Result<UserProfile> {
        self.get("api/v1/users/@me")
    }
    pub fn health(base_url: &str, readiness: bool) -> Result<HealthResponse> {
        let (http, base) = Self::transport(base_url)?;
        Self::decode(
            http.get(
                base.join(if readiness {
                    "health/ready"
                } else {
                    "health/live"
                })
                .map_err(|_| BackendError::InvalidResponse)?,
            )
            .send()
            .map_err(|_| BackendError::Transport)?,
        )
    }
    pub fn guilds(&self) -> Result<Vec<Guild>> {
        self.get("api/v1/guilds")
    }
    pub fn guild(&self, guild_id: &str) -> Result<Guild> {
        self.get(&format!("api/v1/guilds/{}", id(guild_id)?))
    }
    pub fn create_guild(&self, value: &str) -> Result<Guild> {
        self.write(Method::POST, "api/v1/guilds", json!({"name":name(value)?}))
    }
    pub fn rename_guild(&self, guild_id: &str, value: &str) -> Result<Guild> {
        self.write(
            Method::PATCH,
            &format!("api/v1/guilds/{}", id(guild_id)?),
            json!({"name":name(value)?}),
        )
    }
    pub fn delete_guild(&self, guild_id: &str) -> Result<()> {
        self.empty(Method::DELETE, &format!("api/v1/guilds/{}", id(guild_id)?))
    }
    pub fn leave_guild(&self, guild_id: &str) -> Result<()> {
        self.empty(
            Method::DELETE,
            &format!("api/v1/guilds/{}/members/@me", id(guild_id)?),
        )
    }
    pub fn channels(&self, guild_id: &str) -> Result<Vec<BackendChannel>> {
        self.get(&format!("api/v1/guilds/{}/channels", id(guild_id)?))
    }
    pub fn channel(&self, channel_id: &str) -> Result<BackendChannel> {
        self.get(&format!("api/v1/channels/{}", id(channel_id)?))
    }
    pub fn create_channel(
        &self,
        guild_id: &str,
        value: &str,
        kind: ChannelKind,
        position: i32,
    ) -> Result<BackendChannel> {
        if position < 0 {
            return Err(invalid("La position du salon doit être positive ou nulle."));
        }
        self.write(
            Method::POST,
            &format!("api/v1/guilds/{}/channels", id(guild_id)?),
            json!({"name":name(value)?,"kind":kind,"position":position}),
        )
    }
    pub fn update_channel(
        &self,
        channel_id: &str,
        value: &str,
        position: i32,
    ) -> Result<BackendChannel> {
        if position < 0 {
            return Err(invalid("La position du salon doit être positive ou nulle."));
        }
        self.write(
            Method::PATCH,
            &format!("api/v1/channels/{}", id(channel_id)?),
            json!({"name":name(value)?,"position":position}),
        )
    }
    pub fn delete_channel(&self, channel_id: &str) -> Result<()> {
        self.empty(
            Method::DELETE,
            &format!("api/v1/channels/{}", id(channel_id)?),
        )
    }
    pub fn members(&self, guild_id: &str) -> Result<Vec<GuildMember>> {
        self.get(&format!("api/v1/guilds/{}/members", id(guild_id)?))
    }
    pub fn kick_member(&self, guild_id: &str, user_id: &str) -> Result<()> {
        self.empty(
            Method::DELETE,
            &format!("api/v1/guilds/{}/members/{}", id(guild_id)?, id(user_id)?),
        )
    }
    pub fn roles(&self, guild_id: &str) -> Result<Vec<Role>> {
        self.get(&format!("api/v1/guilds/{}/roles", id(guild_id)?))
    }
    pub fn create_role(&self, guild_id: &str, value: &str, permissions: i64) -> Result<Role> {
        mask(permissions)?;
        self.write(
            Method::POST,
            &format!("api/v1/guilds/{}/roles", id(guild_id)?),
            json!({"name":name(value)?,"permissions":permissions}),
        )
    }
    pub fn update_role(
        &self,
        guild_id: &str,
        role_id: &str,
        value: Option<&str>,
        permissions: i64,
    ) -> Result<Role> {
        mask(permissions)?;
        let mut body = json!({"permissions":permissions});
        if let Some(value) = value {
            body["name"] = json!(name(value)?);
        }
        self.write(
            Method::PATCH,
            &format!("api/v1/guilds/{}/roles/{}", id(guild_id)?, id(role_id)?),
            body,
        )
    }
    pub fn delete_role(&self, guild_id: &str, role_id: &str) -> Result<()> {
        self.empty(
            Method::DELETE,
            &format!("api/v1/guilds/{}/roles/{}", id(guild_id)?, id(role_id)?),
        )
    }
    pub fn set_member_role(
        &self,
        guild_id: &str,
        user_id: &str,
        role_id: &str,
        assigned: bool,
    ) -> Result<()> {
        self.empty(
            if assigned {
                Method::PUT
            } else {
                Method::DELETE
            },
            &format!(
                "api/v1/guilds/{}/members/{}/roles/{}",
                id(guild_id)?,
                id(user_id)?,
                id(role_id)?
            ),
        )
    }
    pub fn invites(&self, guild_id: &str) -> Result<Vec<Invite>> {
        self.get(&format!("api/v1/guilds/{}/invites", id(guild_id)?))
    }
    pub fn create_invite(
        &self,
        guild_id: &str,
        expires_in_seconds: Option<i64>,
        max_uses: Option<i64>,
    ) -> Result<CreatedInvite> {
        if expires_in_seconds.is_some_and(|value| !(1..=604_800).contains(&value))
            || max_uses.is_some_and(|value| !(1..=1_000_000).contains(&value))
        {
            return Err(invalid(
                "La durée doit être de 1 à 604 800 secondes, et la limite de 1 à 1 000 000 utilisations.",
            ));
        }
        self.write(
            Method::POST,
            &format!("api/v1/guilds/{}/invites", id(guild_id)?),
            json!({"expires_in_seconds":expires_in_seconds,"max_uses":max_uses}),
        )
    }
    pub fn revoke_invite(&self, guild_id: &str, invite_id: &str) -> Result<()> {
        self.empty(
            Method::DELETE,
            &format!("api/v1/guilds/{}/invites/{}", id(guild_id)?, id(invite_id)?),
        )
    }
    pub fn accept_invite(&self, token: &str) -> Result<Guild> {
        if token.trim().is_empty() {
            return Err(invalid("Saisissez le code d’invitation."));
        }
        self.write(
            Method::POST,
            "api/v1/invites/accept",
            json!({"token":token.trim()}),
        )
    }
    pub fn channel_permissions(&self, channel_id: &str) -> Result<ChannelPermissions> {
        self.get(&format!(
            "api/v1/channels/{}/permissions/@me",
            id(channel_id)?
        ))
    }
    pub fn overrides(&self, channel_id: &str) -> Result<Vec<ChannelOverride>> {
        self.get(&format!(
            "api/v1/channels/{}/permission-overrides",
            id(channel_id)?
        ))
    }
    pub fn put_override(
        &self,
        channel_id: &str,
        role_id: Option<&str>,
        member_id: Option<&str>,
        allow: i64,
        deny: i64,
    ) -> Result<ChannelOverride> {
        mask(allow)?;
        mask(deny)?;
        if role_id.is_some() == member_id.is_some() || allow & deny != 0 {
            return Err(invalid(
                "Choisissez une seule cible et des permissions autorisées/refusées disjointes.",
            ));
        }
        self.write(Method::PUT, &format!("api/v1/channels/{}/permission-overrides", id(channel_id)?), json!({"role_id":role_id.map(id).transpose()?,"member_id":member_id.map(id).transpose()?,"allow_permissions":allow,"deny_permissions":deny}))
    }
    pub fn delete_override(&self, channel_id: &str, override_id: &str) -> Result<()> {
        self.empty(
            Method::DELETE,
            &format!(
                "api/v1/channels/{}/permission-overrides/{}",
                id(channel_id)?,
                id(override_id)?
            ),
        )
    }
    pub fn community(&self, guild_id: &str) -> Result<Community> {
        let guild = self.guild(guild_id)?;
        let channels = self.channels(guild_id)?;
        let members = self.members(guild_id)?;
        let roles = self.roles(guild_id)?;
        let permissions = guild_permissions(&guild, &self.user.id, &members, &roles);
        Ok(Community {
            guild,
            channels,
            members,
            roles,
            permissions,
        })
    }
}
impl Drop for BackendSession {
    fn drop(&mut self) {
        self.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn transport_rejects_insecure_remote_hosts_and_url_credentials() {
        for url in [
            "http://example.com",
            "https://user:secret@example.com",
            "http://localhost/api",
            "https://example.com/?token=secret",
            "file:///tmp/a",
            "http://localhost/#x",
        ] {
            assert!(BackendSession::transport(url).is_err());
        }
        for url in [
            "http://localhost:3000",
            "http://127.0.0.1:3000",
            "http://[::1]:3000",
            "https://example.com",
        ] {
            assert!(BackendSession::transport(url).is_ok());
        }
    }
    #[test]
    fn account_names_match_server_constraints() {
        for value in ["ab", "a b", "élève", &"a".repeat(33)] {
            assert!(account_name(value).is_err());
        }
        assert_eq!(account_name(" Alice_Test-1. ").unwrap(), "Alice_Test-1.");
    }
    #[test]
    fn path_identifiers_cannot_escape_the_resource() {
        for value in ["../auth/logout", "a/b", "?token=secret", ""] {
            assert!(id(value).is_err());
        }
        assert_eq!(
            id("550E8400-E29B-41D4-A716-446655440000").unwrap(),
            "550e8400-e29b-41d4-a716-446655440000"
        );
    }
}
