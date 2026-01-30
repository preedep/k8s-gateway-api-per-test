use warp::Filter;
use std::collections::HashMap;

#[derive(serde::Deserialize)]
struct EchoRequest {
    message: Option<String>,
}

#[derive(serde::Serialize)]
struct EchoResponse {
    message: String,
    method: String,
    path: String,
    headers: HashMap<String, String>,
    timestamp: String,
}

#[tokio::main]
async fn main() {
    // GET /echo - simple hello world
    let echo_get = warp::path("echo")
        .and(warp::get())
        .map(|| {
            let response = EchoResponse {
                message: "Hello from Rust Echo Service!".to_string(),
                method: "GET".to_string(),
                path: "/echo".to_string(),
                headers: HashMap::new(),
                timestamp: chrono::Utc::now().to_rfc3339(),
            };
            warp::reply::json(&response)
        });

    // POST /echo - echo back the request
    let echo_post = warp::path("echo")
        .and(warp::post())
        .and(warp::body::json())
        .and(warp::header::headers_cloned())
        .map(|req: EchoRequest, headers: warp::http::HeaderMap| {
            let mut header_map = HashMap::new();
            for (name, value) in headers {
                if let Ok(value_str) = value.to_str() {
                    header_map.insert(name.to_string(), value_str.to_string());
                }
            }

            let response = EchoResponse {
                message: req.message.unwrap_or_else(|| "Echo from Rust!".to_string()),
                method: "POST".to_string(),
                path: "/echo".to_string(),
                headers: header_map,
                timestamp: chrono::Utc::now().to_rfc3339(),
            };
            warp::reply::json(&response)
        });

    // Health check endpoint
    let health = warp::path("health")
        .and(warp::get())
        .map(|| {
            warp::reply::json(&serde_json::json!({
                "status": "healthy",
                "service": "rust-echo-service"
            }))
        });

    let routes = echo_get.or(echo_post).or(health);

    println!("Rust Echo Service starting on 0.0.0.0:8080");
    
    warp::serve(routes)
        .run(([0, 0, 0, 0], 8080))
        .await;
}
