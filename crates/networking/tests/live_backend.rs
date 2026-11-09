//! Opt-in smoke test: creates two isolated accounts and removes its guild and sessions.
use chat_core::community::ChannelKind;
use chat_networking::backend::{BackendError, BackendSession};
use std::time::{SystemTime, UNIX_EPOCH};

struct Cleanup<'a> {
    owner: &'a BackendSession,
    guild_id: String,
}
impl Drop for Cleanup<'_> {
    fn drop(&mut self) {
        let _ = self.owner.delete_guild(&self.guild_id);
    }
}

#[test]
#[ignore = "requires the running backend and creates isolated test accounts"]
fn published_community_api_round_trip() {
    let base =
        std::env::var("DISCORD_BACKEND_URL").unwrap_or_else(|_| "http://localhost:3000".into());
    assert_eq!(BackendSession::health(&base, false).unwrap().status, "ok");
    assert_eq!(BackendSession::health(&base, true).unwrap().status, "ok");
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let email = format!("client-owner-{suffix}@example.invalid");
    let password = "ClientIntegration!2026-LongPassword";
    let owner =
        BackendSession::authenticate(&base, &email, password, Some(&format!("owner_{suffix}")))
            .unwrap();
    let member = BackendSession::authenticate(
        &base,
        &format!("client-member-{suffix}@example.invalid"),
        password,
        Some(&format!("member_{suffix}")),
    )
    .unwrap();
    let login = BackendSession::authenticate(&base, &email, password, None).unwrap();
    assert_eq!(login.profile().unwrap().id, owner.user.id);
    login.logout().unwrap();
    assert!(matches!(login.profile(), Err(BackendError::SessionClosed)));
    let guild = owner.create_guild("  Client integration 🦀  ").unwrap();
    let cleanup = Cleanup {
        owner: &owner,
        guild_id: guild.id.clone(),
    };
    assert_eq!(guild.name, "Client integration 🦀");
    assert!(
        owner
            .guilds()
            .unwrap()
            .iter()
            .any(|item| item.id == guild.id)
    );
    assert_eq!(owner.guild(&guild.id).unwrap().owner_id, owner.user.id);
    assert_eq!(
        owner.rename_guild(&guild.id, "Renamed 🦀").unwrap().name,
        "Renamed 🦀"
    );
    let channel = owner
        .create_channel(&guild.id, "general", ChannelKind::Text, 0)
        .unwrap();
    let voice = owner
        .create_channel(&guild.id, "voice", ChannelKind::Voice, 1)
        .unwrap();
    assert_eq!(owner.channel(&voice.id).unwrap().kind, ChannelKind::Voice);
    assert_eq!(owner.channels(&guild.id).unwrap().len(), 2);
    assert_eq!(
        owner
            .update_channel(&channel.id, "café", 2)
            .unwrap()
            .position,
        2
    );
    assert_eq!(
        owner.channel_permissions(&channel.id).unwrap().permissions,
        127
    );
    let role = owner.create_role(&guild.id, "Reader", 1).unwrap();
    assert_eq!(
        owner
            .update_role(&guild.id, &role.id, Some("Writer"), 3)
            .unwrap()
            .name,
        "Writer"
    );
    assert!(
        owner
            .roles(&guild.id)
            .unwrap()
            .iter()
            .any(|item| item.id == role.id)
    );
    let invitation = owner
        .create_invite(&guild.id, Some(3600), Some(10))
        .unwrap();
    assert_eq!(
        member.accept_invite(&invitation.token).unwrap().id,
        guild.id
    );
    assert_eq!(owner.members(&guild.id).unwrap().len(), 2);
    owner
        .set_member_role(&guild.id, &member.user.id, &role.id, true)
        .unwrap();
    assert!(
        owner
            .members(&guild.id)
            .unwrap()
            .iter()
            .find(|item| item.user_id == member.user.id)
            .unwrap()
            .role_ids
            .contains(&role.id)
    );
    owner
        .set_member_role(&guild.id, &member.user.id, &role.id, false)
        .unwrap();
    let override_ = owner
        .put_override(&channel.id, Some(&role.id), None, 2, 0)
        .unwrap();
    assert_eq!(owner.overrides(&channel.id).unwrap().len(), 1);
    owner.delete_override(&channel.id, &override_.id).unwrap();
    let override_ = owner
        .put_override(&channel.id, None, Some(&member.user.id), 0, 1)
        .unwrap();
    assert!(
        member
            .channels(&guild.id)
            .unwrap()
            .iter()
            .all(|item| item.id != channel.id)
    );
    assert!(matches!(
        member.channel(&channel.id),
        Err(BackendError::Http { status: 404, .. })
    ));
    owner.delete_override(&channel.id, &override_.id).unwrap();
    assert_eq!(owner.community(&guild.id).unwrap().permissions, 127);
    assert_eq!(member.community(&guild.id).unwrap().permissions, 3);
    assert!(matches!(
        member.delete_guild(&guild.id),
        Err(BackendError::Http { status: 403, .. })
    ));
    owner.kick_member(&guild.id, &member.user.id).unwrap();
    member.accept_invite(&invitation.token).unwrap();
    member.leave_guild(&guild.id).unwrap();
    assert_eq!(owner.members(&guild.id).unwrap().len(), 1);
    assert_eq!(owner.invites(&guild.id).unwrap().len(), 1);
    owner
        .revoke_invite(&guild.id, &invitation.invite.id)
        .unwrap();
    assert!(owner.invites(&guild.id).unwrap()[0].revoked_at.is_some());
    assert!(member.accept_invite(&invitation.token).is_err());
    owner.delete_role(&guild.id, &role.id).unwrap();
    owner.delete_channel(&channel.id).unwrap();
    owner.delete_channel(&voice.id).unwrap();
    drop(cleanup);
    assert!(
        owner
            .guilds()
            .unwrap()
            .iter()
            .all(|item| item.id != guild.id)
    );
    member.logout().unwrap();
    owner.logout().unwrap();
}
