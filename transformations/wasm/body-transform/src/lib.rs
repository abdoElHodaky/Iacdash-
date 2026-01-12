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
                        
                        // Add request validation
                        if let Some(email) = obj.get("email") {
                            if let Some(email_str) = email.as_str() {
                                if !email_str.contains("@") {
                                    obj.insert("validation_error".to_string(), Value::String("Invalid email format".to_string()));
                                }
                            }
                        }
                        
                        // Remove sensitive fields
                        obj.remove("password");
                        obj.remove("secret_key");
                        obj.remove("api_key");
                        
                        // Add request tracking
                        if let Some(request_id) = self.get_http_request_header("x-request-id") {
                            obj.insert("request_id".to_string(), Value::String(request_id));
                        }
                    }
                    
                    let transformed_body = serde_json::to_string(&json_value).unwrap();
                    self.set_http_request_body(0, body_size, &transformed_body.as_bytes());
                    
                    // Update content length
                    self.set_http_request_header("content-length", Some(&transformed_body.len().to_string()));
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
                        
                        // Add response tracking
                        if let Some(request_id) = self.get_http_request_header("x-request-id") {
                            obj.insert("request_id".to_string(), Value::String(request_id));
                        }
                        
                        // Filter sensitive response data
                        obj.remove("internal_id");
                        obj.remove("debug_info");
                        obj.remove("database_query");
                        obj.remove("server_info");
                        
                        // Add pagination info if it's a list response
                        if obj.contains_key("items") {
                            if let Some(items) = obj.get("items") {
                                if let Some(items_array) = items.as_array() {
                                    obj.insert("total_count".to_string(), Value::Number(serde_json::Number::from(items_array.len())));
                                }
                            }
                        }
                        
                        // Add response status metadata
                        obj.insert("success".to_string(), Value::Bool(true));
                    }
                    
                    let transformed_body = serde_json::to_string(&json_value).unwrap();
                    self.set_http_response_body(0, body_size, &transformed_body.as_bytes());
                    
                    // Update content length
                    self.set_http_response_header("content-length", Some(&transformed_body.len().to_string()));
                }
            }
        }
        
        Action::Continue
    }
}

