use chat_core::community::ChannelKind;
use chat_networking::backend::{BackendError, BackendSession};
use serde_json::{Value, json};
use std::{
    io::{Read, Write},
    net::TcpListener,
    thread,
};

const ID: &str = "550e8400-e29b-41d4-a716-446655440000";
fn profile() -> Value {
    json!({"id":ID,"username":"client_user","email":"u@example.invalid","created_at":"2026-10-14T10:00:00Z"})
}
fn auth() -> Value {
    json!({"user":profile(),"token":"test-session-secret","token_type":"Bearer","expires_at":"2026-10-15T10:00:00Z"})
}
struct Step {
    method: &'static str,
    path: &'static str,
    body: Option<Value>,
    status: u16,
    response: String,
    authenticated: bool,
    location: Option<String>,
    delay: std::time::Duration,
    started: Option<std::sync::mpsc::Sender<()>>,
}
fn step(
    method: &'static str,
    path: &'static str,
    body: Option<Value>,
    status: u16,
    response: Value,
    authenticated: bool,
) -> Step {
    Step {
        method,
        path,
        body,
        status,
        response: response.to_string(),
        authenticated,
        location: None,
        delay: std::time::Duration::ZERO,
        started: None,
    }
}
fn fixture(steps: Vec<Step>) -> (String, thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let handle = thread::spawn(move || {
        for step in steps {
            let (mut stream, _) = listener.accept().unwrap();
            stream
                .set_read_timeout(Some(std::time::Duration::from_secs(3)))
                .unwrap();
            let mut bytes = Vec::new();
            let (headers, body) = loop {
                let mut buf = [0; 4096];
                let count = stream.read(&mut buf).unwrap();
                assert_ne!(count, 0);
                bytes.extend_from_slice(&buf[..count]);
                if let Some(end) = bytes.windows(4).position(|item| item == b"\r\n\r\n") {
                    let headers = String::from_utf8(bytes[..end].to_vec()).unwrap();
                    let length: usize = headers
                        .lines()
                        .find_map(|line| {
                            line.to_ascii_lowercase()
                                .strip_prefix("content-length: ")
                                .map(str::to_owned)
                        })
                        .map(|value| value.parse().unwrap())
                        .unwrap_or(0);
                    if bytes.len() >= end + 4 + length {
                        break (headers, bytes[end + 4..end + 4 + length].to_vec());
                    }
                }
            };
            assert_eq!(
                headers.lines().next().unwrap(),
                format!("{} {} HTTP/1.1", step.method, step.path)
            );
            assert_eq!(
                headers
                    .to_ascii_lowercase()
                    .contains("authorization: bearer test-session-secret"),
                step.authenticated
            );
            match step.body {
                Some(expected) => {
                    assert_eq!(serde_json::from_slice::<Value>(&body).unwrap(), expected)
                }
                None => assert!(body.is_empty()),
            }
            if let Some(started) = step.started {
                started.send(()).unwrap();
            }
            thread::sleep(step.delay);
            let location = step
                .location
                .map(|url| format!("Location: {url}\r\n"))
                .unwrap_or_default();
            let response = if step.status == 204 {
                String::new()
            } else {
                step.response
            };
            write!(stream, "HTTP/1.1 {} Test\r\n{}Content-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", step.status, location, response.len(), response).unwrap();
        }
    });
    (url, handle)
}
fn login_step() -> Step {
    step(
        "POST",
        "/api/v1/auth/login",
        Some(json!({"email":"u@example.invalid","password":"password"})),
        200,
        auth(),
        false,
    )
}
#[test]
fn auth_body_bearer_unicode_profile_and_logout_follow_contract() {
    let (url, server) = fixture(vec![
        login_step(),
        step("GET", "/api/v1/users/@me", None, 200, profile(), true),
        step("POST", "/api/v1/auth/logout", None, 204, Value::Null, true),
    ]);
    let client =
        BackendSession::authenticate(&url, " u@example.invalid ", "password", None).unwrap();
    assert_eq!(client.profile().unwrap().username, "client_user");
    client.logout().unwrap();
    client.close();
    assert!(matches!(client.guilds(), Err(BackendError::SessionClosed)));
    server.join().unwrap();
}
#[test]
fn registration_and_session_expiry_are_not_demo_fallbacks() {
    let password = "long-test-password";
    let (url, server) = fixture(vec![
        step(
            "POST",
            "/api/v1/auth/register",
            Some(json!({"username":"client_user","email":"u@example.invalid","password":password})),
            201,
            auth(),
            false,
        ),
        step(
            "GET",
            "/api/v1/guilds",
            None,
            401,
            json!({"detail":"Session expired"}),
            true,
        ),
    ]);
    let client =
        BackendSession::authenticate(&url, "u@example.invalid", password, Some("client_user"))
            .unwrap();
    assert!(
        matches!(client.guilds(), Err(BackendError::Http { status: 401, detail }) if detail == "Session expired")
    );
    assert!(matches!(client.profile(), Err(BackendError::SessionClosed)));
    server.join().unwrap();
}
#[test]
fn invalid_mutations_are_rejected_before_http() {
    let (url, server) = fixture(vec![login_step()]);
    let client = BackendSession::authenticate(&url, "u@example.invalid", "password", None).unwrap();
    assert!(client.create_guild(" \n").is_err());
    assert!(client.delete_guild("../auth/logout").is_err());
    assert!(
        client
            .create_channel(ID, "x", ChannelKind::Text, -1)
            .is_err()
    );
    assert!(client.create_role(ID, "x", 128).is_err());
    assert!(client.create_invite(ID, Some(0), None).is_err());
    assert!(client.put_override(ID, Some(ID), Some(ID), 1, 0).is_err());
    assert!(client.put_override(ID, Some(ID), None, 1, 1).is_err());
    assert!(client.accept_invite("  ").is_err());
    server.join().unwrap();
}
#[test]
fn malformed_success_response_is_an_error() {
    let (url, server) = fixture(vec![
        login_step(),
        step(
            "GET",
            "/api/v1/guilds",
            None,
            200,
            json!({"unexpected":"shape"}),
            true,
        ),
    ]);
    let client = BackendSession::authenticate(&url, "u@example.invalid", "password", None).unwrap();
    assert!(matches!(
        client.guilds(),
        Err(BackendError::InvalidResponse)
    ));
    server.join().unwrap();
}
#[test]
fn non_auth_errors_preserve_session_and_problem_details() {
    let (url, server) = fixture(vec![
        login_step(),
        step(
            "GET",
            "/api/v1/guilds",
            None,
            503,
            json!({"detail":"Database unavailable"}),
            true,
        ),
        step("GET", "/api/v1/users/@me", None, 200, profile(), true),
    ]);
    let client = BackendSession::authenticate(&url, "u@example.invalid", "password", None).unwrap();
    assert!(
        matches!(client.guilds(), Err(BackendError::Http { status: 503, detail }) if detail == "Database unavailable")
    );
    assert_eq!(client.profile().unwrap().id, ID);
    server.join().unwrap();
}

#[test]
fn redirects_cannot_forward_session_credentials() {
    let target = TcpListener::bind("127.0.0.1:0").unwrap();
    target.set_nonblocking(true).unwrap();
    let mut redirect = step(
        "GET",
        "/api/v1/guilds",
        None,
        302,
        json!({"detail":"Redirect refused"}),
        true,
    );
    redirect.location = Some(format!("http://{}/capture", target.local_addr().unwrap()));
    let (url, server) = fixture(vec![login_step(), redirect]);
    let client = BackendSession::authenticate(&url, "u@example.invalid", "password", None).unwrap();
    assert!(matches!(
        client.guilds(),
        Err(BackendError::Http { status: 302, .. })
    ));
    assert_eq!(
        target.accept().unwrap_err().kind(),
        std::io::ErrorKind::WouldBlock
    );
    server.join().unwrap();
}
#[test]
fn closing_during_io_discards_successful_responses() {
    let (started, ready) = std::sync::mpsc::channel();
    let mut response = step("GET", "/api/v1/guilds", None, 200, json!([]), true);
    response.started = Some(started);
    response.delay = std::time::Duration::from_millis(50);
    let (url, server) = fixture(vec![login_step(), response]);
    let client = std::sync::Arc::new(
        BackendSession::authenticate(&url, "u@example.invalid", "password", None).unwrap(),
    );
    let worker = {
        let client = client.clone();
        thread::spawn(move || client.guilds())
    };
    ready
        .recv_timeout(std::time::Duration::from_secs(2))
        .unwrap();
    client.close();
    assert!(matches!(
        worker.join().unwrap(),
        Err(BackendError::SessionClosed)
    ));
    server.join().unwrap();
}
