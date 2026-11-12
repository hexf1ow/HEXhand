//! Remote workspace support.
//!
//! Level 2 shape: HEXhand runs here in a container, but the folder it works in lives on
//! another machine (the Windows box). A small connector runs next to that folder and
//! exposes the same JSON-RPC surface; when `CATDESK_REMOTE_URL` is set every tool call is
//! forwarded to it, so `read`/`write`/`edit`/`search`/`delete` and the command tools act on
//! that machine's filesystem instead of this container's.

use serde_json::{json, Value};
use std::time::Duration;

/// Returns (url, token) when a remote connector is configured.
pub fn remote_endpoint() -> Option<(String, String)> {
    let url = std::env::var("CATDESK_REMOTE_URL").ok()?;
    let url = url.trim().to_string();
    if url.is_empty() {
        return None;
    }
    let token = std::env::var("CATDESK_REMOTE_TOKEN").unwrap_or_default();
    Some((url, token))
}

/// Forward one JSON-RPC call to the connector. Returns the connector's raw JSON-RPC reply.
pub async fn forward(method: &str, id: Option<Value>, params: &Value) -> Option<Value> {
    let (url, token) = remote_endpoint()?;
    let body = json!({
        "jsonrpc": "2.0",
        "id": id,
        "method": method,
        "params": params,
    });

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(120))
        .build()
        .ok()?;
    let mut request = client.post(&url).json(&body);
    if !token.is_empty() {
        request = request.header("Authorization", format!("Bearer {token}"));
    }

    let response = request.send().await.ok()?;
    response.json::<Value>().await.ok()
}
