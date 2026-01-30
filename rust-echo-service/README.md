# Rust Echo Service

A simple HTTP echo service built with Rust and the Warp web framework, designed for Kubernetes gateway performance testing.

## Features

- **GET /echo** - Returns a hello world message with metadata
- **POST /echo** - Echoes back the request JSON with additional metadata
- **GET /health** - Health check endpoint
- Lightweight and fast for performance testing
- Containerized for easy deployment

## API Endpoints

### GET /echo
```json
{
  "message": "Hello from Rust Echo Service!",
  "method": "GET", 
  "path": "/echo",
  "headers": {},
  "timestamp": "2024-01-30T12:00:00Z"
}
```

### POST /echo
Request:
```json
{
  "message": "test message"
}
```

Response:
```json
{
  "message": "test message",
  "method": "POST",
  "path": "/echo", 
  "headers": {
    "content-type": "application/json",
    "host": "localhost"
  },
  "timestamp": "2024-01-30T12:00:00Z"
}
```

### GET /health
```json
{
  "status": "healthy",
  "service": "rust-echo-service"
}
```

## Building and Running

### Local Development
```bash
cargo run
```

### Docker Build
```bash
docker build -t rust-echo-service:latest .
```

### Kubernetes Deployment
Use the provided deployment script:
```bash
bash ../perf-routing/15-rust-app.sh
```

## Performance Characteristics

- Built with Rust for maximum performance
- Uses async runtime (Tokio) for high concurrency
- Minimal memory footprint
- Fast JSON serialization/deserialization
- Optimized for HTTP routing performance tests

## Technology Stack

- **Rust** - Systems programming language
- **Tokio** - Asynchronous runtime
- **Warp** - Web framework
- **Serde** - JSON serialization
- **Chrono** - Timestamp handling
