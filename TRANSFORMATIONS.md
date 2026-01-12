# 🔄 Custom Request/Response Transformations

Complete guide for implementing custom transformations using Envoy Filters, Lua scripts, OPA policies, and WebAssembly (WASM) plugins.

## 📑 Table of Contents

- [Overview](#overview)
- [Envoy Filters](#envoy-filters)
- [Lua Transformations](#lua-transformations)
- [OPA Policy Engine](#opa-policy-engine)
- [WebAssembly (WASM) Plugins](#webassembly-wasm-plugins)
- [Body Transformations](#body-transformations)
- [Header Manipulation](#header-manipulation)
- [Authentication & Authorization](#authentication--authorization)
- [Rate Limiting](#rate-limiting)
- [Examples](#examples)

---

## 🎯 Overview

The transformation engine provides multiple layers for request/response modification:

```
Incoming Request
       ↓
Header Transformations (Envoy/Lua/WASM)
       ↓
Authentication (OPA/WASM)
       ↓
Body Transformations (Lua/WASM)
       ↓
Rate Limiting (Envoy)
       ↓
Backend Service
       ↓
Response Transformations (Lua/WASM)
       ↓
Outgoing Response
```

### Transformation Technologies

| Technology | Use Case | Performance | Complexity |
|------------|----------|-------------|------------|
| **Envoy Filters** | Header manipulation, routing | High | Low |
| **Lua Scripts** | Request/response modification | Medium | Medium |
| **OPA Policies** | Authorization, validation | Medium | Medium |
| **WASM Plugins** | Complex transformations | High | High |

---

## 🔧 Envoy Filters

### Basic Header Manipulation

```yaml
# transformations/envoy-filters/header-manipulation.yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: header-manipulation
  namespace: istio-ingress
spec:
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: GATEWAY
      listener:
        filterChain:
          filter:
            name: "envoy.filters.network.http_connection_manager"
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.lua
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
          inline_code: |
            function envoy_on_request(request_handle)
              -- Add security headers
              request_handle:headers():add("X-Request-ID", request_handle:headers():get(":authority") .. "-" .. os.time())
              request_handle:headers():add("X-Forwarded-Proto", "https")
              
              -- Remove sensitive headers
              request_handle:headers():remove("X-Internal-Token")
            end
            
            function envoy_on_response(response_handle)
              -- Add security headers
              response_handle:headers():add("X-Content-Type-Options", "nosniff")
              response_handle:headers():add("X-Frame-Options", "DENY")
              response_handle:headers():add("X-XSS-Protection", "1; mode=block")
              response_handle:headers():add("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
            end
```

### Request Routing Based on Headers

```yaml
# transformations/envoy-filters/conditional-routing.yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: conditional-routing
  namespace: istio-ingress
spec:
  configPatches:
  - applyTo: HTTP_ROUTE
    match:
      context: GATEWAY
    patch:
      operation: INSERT_BEFORE
      value:
        match:
          headers:
          - name: "X-Canary"
            exact_match: "true"
        route:
          cluster: outbound|8080||canary-service.default.svc.cluster.local
```

---

## 🐍 Lua Transformations

### Request Body Transformation

```yaml
# transformations/lua-scripts/body-transform.yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: request-body-transform
  namespace: default
spec:
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: SIDECAR_INBOUND
      listener:
        filterChain:
          filter:
            name: "envoy.filters.network.http_connection_manager"
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.lua
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
          inline_code: |
            function envoy_on_request(request_handle)
              local body = request_handle:body()
              if body then
                local json = require("json")
                local data = json.decode(body:getBytes(0, body:length()))
                
                -- Transform request data
                if data.user_id then
                  data.user_id = "user_" .. data.user_id
                end
                
                -- Add timestamp
                data.timestamp = os.time()
                
                -- Add request metadata
                data.source_ip = request_handle:headers():get("x-forwarded-for")
                
                local new_body = json.encode(data)
                request_handle:body():setBytes(new_body)
                request_handle:headers():add("content-length", string.len(new_body))
              end
            end
```

### Response Data Filtering

```yaml
# transformations/lua-scripts/response-filter.yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: response-data-filter
  namespace: default
spec:
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: SIDECAR_OUTBOUND
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.lua
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
          inline_code: |
            function envoy_on_response(response_handle)
              local body = response_handle:body()
              if body then
                local json = require("json")
                local data = json.decode(body:getBytes(0, body:length()))
                
                -- Remove sensitive fields
                if data.password then
                  data.password = nil
                end
                if data.secret_key then
                  data.secret_key = nil
                end
                
                -- Add response metadata
                data.response_time = response_handle:headers():get("x-response-time")
                data.server_version = "v1.0.0"
                
                local new_body = json.encode(data)
                response_handle:body():setBytes(new_body)
                response_handle:headers():add("content-length", string.len(new_body))
              end
            end
```

---

## 🛡️ OPA Policy Engine

### Authorization Policies

```yaml
# transformations/opa-policies/authorization.yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: opa-authorization
  namespace: istio-ingress
spec:
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: GATEWAY
      listener:
        filterChain:
          filter:
            name: "envoy.filters.network.http_connection_manager"
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.ext_authz
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.ext_authz.v3.ExtAuthz
          grpc_service:
            envoy_grpc:
              cluster_name: opa-service
          transport_api_version: V3
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: opa-policy
  namespace: istio-ingress
data:
  policy.rego: |
    package envoy.authz
    
    import future.keywords.if
    import future.keywords.in
    
    default allow := false
    
    # Allow requests with valid JWT
    allow if {
        valid_jwt
        valid_permissions
    }
    
    # Check JWT validity
    valid_jwt if {
        token := input.attributes.request.http.headers.authorization
        startswith(token, "Bearer ")
        jwt_token := substring(token, 7, -1)
        io.jwt.verify_rs256(jwt_token, data.public_key)
    }
    
    # Check user permissions
    valid_permissions if {
        token := input.attributes.request.http.headers.authorization
        jwt_token := substring(token, 7, -1)
        payload := io.jwt.decode(jwt_token)[1]
        
        required_permission := sprintf("%s:%s", [
            input.attributes.request.http.method,
            input.attributes.request.http.path
        ])
        
        required_permission in payload.permissions
    }
    
    # Rate limiting based on user tier
    rate_limit if {
        token := input.attributes.request.http.headers.authorization
        jwt_token := substring(token, 7, -1)
        payload := io.jwt.decode(jwt_token)[1]
        
        payload.tier == "premium"
        count(input.attributes.request.http.headers["x-request-count"]) < 1000
    }
    
    rate_limit if {
        token := input.attributes.request.http.headers.authorization
        jwt_token := substring(token, 7, -1)
        payload := io.jwt.decode(jwt_token)[1]
        
        payload.tier == "basic"
        count(input.attributes.request.http.headers["x-request-count"]) < 100
    }
```

### Request Validation

```yaml
# transformations/opa-policies/validation.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: opa-validation-policy
  namespace: istio-ingress
data:
  validation.rego: |
    package envoy.validation
    
    import future.keywords.if
    
    default valid := false
    
    # Validate request structure
    valid if {
        input.attributes.request.http.method in ["GET", "POST", "PUT", "DELETE"]
        valid_content_type
        valid_request_size
    }
    
    # Check content type for POST/PUT requests
    valid_content_type if {
        input.attributes.request.http.method in ["GET", "DELETE"]
    }
    
    valid_content_type if {
        input.attributes.request.http.method in ["POST", "PUT"]
        input.attributes.request.http.headers["content-type"] == "application/json"
    }
    
    # Validate request size
    valid_request_size if {
        content_length := to_number(input.attributes.request.http.headers["content-length"])
        content_length <= 1048576  # 1MB limit
    }
    
    # Validate required headers
    required_headers := ["user-agent", "accept"]
    
    valid if {
        count([h | h := required_headers[_]; input.attributes.request.http.headers[h]]) == count(required_headers)
    }
```

---

## 🚀 WebAssembly (WASM) Plugins

### Header Transformation WASM Plugin

```rust
// transformations/wasm/header-transform/src/lib.rs
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::collections::HashMap;

#[no_mangle]
pub fn _start() {
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_http_context(|_, _| -> Box<dyn HttpContext> {
        Box::new(HeaderTransform::new())
    });
}

struct HeaderTransform {
    config: HashMap<String, String>,
}

impl HeaderTransform {
    fn new() -> Self {
        HeaderTransform {
            config: HashMap::new(),
        }
    }
}

impl Context for HeaderTransform {}

impl HttpContext for HeaderTransform {
    fn on_http_request_headers(&mut self, _num_headers: usize, _end_of_stream: bool) -> Action {
        // Add custom headers
        self.add_http_request_header("X-Custom-Header", "processed-by-wasm");
        self.add_http_request_header("X-Request-Time", &format!("{}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs()));
        
        // Remove sensitive headers
        self.remove_http_request_header("X-Internal-Token");
        
        // Transform user agent
        if let Some(user_agent) = self.get_http_request_header("user-agent") {
            let transformed_ua = format!("Transformed-{}", user_agent);
            self.set_http_request_header("user-agent", Some(&transformed_ua));
        }
        
        Action::Continue
    }
    
    fn on_http_response_headers(&mut self, _num_headers: usize, _end_of_stream: bool) -> Action {
        // Add security headers
        self.add_http_response_header("X-Content-Type-Options", "nosniff");
        self.add_http_response_header("X-Frame-Options", "DENY");
        self.add_http_response_header("X-XSS-Protection", "1; mode=block");
        
        // Add custom response metadata
        self.add_http_response_header("X-Processed-By", "wasm-filter");
        
        Action::Continue
    }
}
```

### Body Transformation WASM Plugin

```rust
// transformations/wasm/body-transform/src/lib.rs
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use serde_json::{Value, Map};

#[no_mangle]
pub fn _start() {
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_http_context(|_, _| -> Box<dyn HttpContext> {
        Box::new(BodyTransform::new())
    });
}

struct BodyTransform {
    request_body: Vec<u8>,
    response_body: Vec<u8>,
}

impl BodyTransform {
    fn new() -> Self {
        BodyTransform {
            request_body: Vec::new(),
            response_body: Vec::new(),
        }
    }
}

impl Context for BodyTransform {}

impl HttpContext for BodyTransform {
    fn on_http_request_body(&mut self, body_size: usize, end_of_stream: bool) -> Action {
        if let Some(body_bytes) = self.get_http_request_body(0, body_size) {
            self.request_body.extend_from_slice(&body_bytes);
        }
        
        if end_of_stream {
            if let Ok(body_str) = String::from_utf8(self.request_body.clone()) {
                if let Ok(mut json_value) = serde_json::from_str::<Value>(&body_str) {
                    // Transform JSON body
                    if let Some(obj) = json_value.as_object_mut() {
                        // Add metadata
                        obj.insert("processed_at".to_string(), Value::String(chrono::Utc::now().to_rfc3339()));
                        obj.insert("processed_by".to_string(), Value::String("wasm-filter".to_string()));
                        
                        // Transform user_id field
                        if let Some(user_id) = obj.get("user_id") {
                            if let Some(id_str) = user_id.as_str() {
                                obj.insert("user_id".to_string(), Value::String(format!("user_{}", id_str)));
                            }
                        }
                        
                        // Remove sensitive fields
                        obj.remove("password");
                        obj.remove("secret_key");
                    }
                    
                    let transformed_body = serde_json::to_string(&json_value).unwrap();
                    self.set_http_request_body(0, body_size, &transformed_body.as_bytes());
                }
            }
        }
        
        Action::Continue
    }
    
    fn on_http_response_body(&mut self, body_size: usize, end_of_stream: bool) -> Action {
        if let Some(body_bytes) = self.get_http_response_body(0, body_size) {
            self.response_body.extend_from_slice(&body_bytes);
        }
        
        if end_of_stream {
            if let Ok(body_str) = String::from_utf8(self.response_body.clone()) {
                if let Ok(mut json_value) = serde_json::from_str::<Value>(&body_str) {
                    // Transform response
                    if let Some(obj) = json_value.as_object_mut() {
                        // Add response metadata
                        obj.insert("response_time".to_string(), Value::String(chrono::Utc::now().to_rfc3339()));
                        obj.insert("version".to_string(), Value::String("v1.0.0".to_string()));
                        
                        // Filter sensitive response data
                        obj.remove("internal_id");
                        obj.remove("debug_info");
                    }
                    
                    let transformed_body = serde_json::to_string(&json_value).unwrap();
                    self.set_http_response_body(0, body_size, &transformed_body.as_bytes());
                }
            }
        }
        
        Action::Continue
    }
}
```

### WASM Plugin Deployment

```yaml
# transformations/envoy-filters/wasm-filters.yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: wasm-header-transform
  namespace: istio-ingress
spec:
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: GATEWAY
      listener:
        filterChain:
          filter:
            name: "envoy.filters.network.http_connection_manager"
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.wasm
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.wasm.v3.Wasm
          config:
            name: "header_transform"
            root_id: "header_transform"
            vm_config:
              vm_id: "header_transform"
              runtime: "envoy.wasm.runtime.v8"
              code:
                local:
                  inline_string: |
                    # Base64 encoded WASM binary would go here
                    # For development, you can use a remote source:
                remote:
                  http_uri:
                    uri: "https://github.com/abdoElHodaky/Iacdash-/releases/download/v1.0.0/header-transform.wasm"
                    cluster: "wasm-cluster"
                    timeout: 10s
---
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: wasm-body-transform
  namespace: default
spec:
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: SIDECAR_INBOUND
      listener:
        filterChain:
          filter:
            name: "envoy.filters.network.http_connection_manager"
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.wasm
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.wasm.v3.Wasm
          config:
            name: "body_transform"
            root_id: "body_transform"
            vm_config:
              vm_id: "body_transform"
              runtime: "envoy.wasm.runtime.v8"
              code:
                remote:
                  http_uri:
                    uri: "https://github.com/abdoElHodaky/Iacdash-/releases/download/v1.0.0/body-transform.wasm"
                    cluster: "wasm-cluster"
                    timeout: 10s
```

---

## 🔄 Examples

### Complete Transformation Pipeline

```yaml
# transformations/examples/complete-pipeline.yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: complete-transformation-pipeline
  namespace: istio-ingress
spec:
  configPatches:
  # 1. Authentication check (OPA)
  - applyTo: HTTP_FILTER
    match:
      context: GATEWAY
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.ext_authz
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.ext_authz.v3.ExtAuthz
          grpc_service:
            envoy_grpc:
              cluster_name: opa-service
  
  # 2. Rate limiting
  - applyTo: HTTP_FILTER
    match:
      context: GATEWAY
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.local_ratelimit
        typed_config:
          "@type": type.googleapis.com/udpa.type.v1.TypedStruct
          type_url: type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
          value:
            stat_prefix: local_rate_limiter
            token_bucket:
              max_tokens: 100
              tokens_per_fill: 100
              fill_interval: 60s
  
  # 3. Header transformation (WASM)
  - applyTo: HTTP_FILTER
    match:
      context: GATEWAY
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.wasm
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.wasm.v3.Wasm
          config:
            name: "header_transform"
            vm_config:
              runtime: "envoy.wasm.runtime.v8"
              code:
                remote:
                  http_uri:
                    uri: "https://github.com/abdoElHodaky/Iacdash-/releases/download/v1.0.0/header-transform.wasm"
                    cluster: "wasm-cluster"
                    timeout: 10s
  
  # 4. Body transformation (Lua)
  - applyTo: HTTP_FILTER
    match:
      context: GATEWAY
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.lua
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
          inline_code: |
            function envoy_on_request(request_handle)
              -- Add request ID for tracing
              local request_id = request_handle:headers():get("x-request-id")
              if not request_id then
                request_id = "req-" .. os.time() .. "-" .. math.random(1000, 9999)
                request_handle:headers():add("x-request-id", request_id)
              end
              
              -- Log request for debugging
              request_handle:logInfo("Processing request: " .. request_id)
            end
```

---

## 🚀 Getting Started

### 1. Deploy Basic Transformations

```bash
# Apply header transformations
kubectl apply -f transformations/envoy-filters/header-manipulation.yaml

# Deploy Lua scripts
kubectl apply -f transformations/lua-scripts/

# Apply OPA policies
kubectl apply -f transformations/opa-policies/
```

### 2. Build and Deploy WASM Plugins

```bash
# Build WASM plugins (requires Rust toolchain)
cd transformations/wasm/header-transform
cargo build --target wasm32-unknown-unknown --release

# Deploy WASM filters
kubectl apply -f transformations/envoy-filters/wasm-filters.yaml
```

### 3. Test Transformations

```bash
# Test header transformations
curl -H "Host: demo.dev.local" \
     -H "X-Test-Header: original" \
     http://localhost/get

# Test body transformations
curl -H "Host: demo.dev.local" \
     -H "Content-Type: application/json" \
     -d '{"user_id": "123", "password": "secret"}' \
     http://localhost/post
```

---

## 📚 Next Steps

- **Advanced WASM**: [Build custom WASM plugins](https://github.com/proxy-wasm/spec)
- **OPA Policies**: [Learn OPA policy language](https://www.openpolicyagent.org/docs/latest/)
- **Envoy Configuration**: [Envoy filter documentation](https://www.envoyproxy.io/docs/envoy/latest/)
- **Service Mesh**: [SERVICE-MESH.md](SERVICE-MESH.md)
- **Security**: [SECURITY.md](SECURITY.md)

---

**Ready to transform your traffic?** Start with basic header manipulation and gradually add more complex transformations!

