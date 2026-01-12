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
        
        // Add security headers for HTTPS enforcement
        if let Some(scheme) = self.get_http_request_header(":scheme") {
            if scheme == "http" {
                self.set_http_request_header(":scheme", Some("https"));
            }
        }
        
        Action::Continue
    }
    
    fn on_http_response_headers(&mut self, _num_headers: usize, _end_of_stream: bool) -> Action {
        // Add security headers
        self.add_http_response_header("X-Content-Type-Options", "nosniff");
        self.add_http_response_header("X-Frame-Options", "DENY");
        self.add_http_response_header("X-XSS-Protection", "1; mode=block");
        self.add_http_response_header("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
        
        // Add custom response metadata
        self.add_http_response_header("X-Processed-By", "wasm-filter");
        self.add_http_response_header("X-Response-Time", &format!("{}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis()));
        
        // CORS headers for API endpoints
        if let Some(origin) = self.get_http_request_header("origin") {
            self.add_http_response_header("Access-Control-Allow-Origin", &origin);
            self.add_http_response_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
            self.add_http_response_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With");
        }
        
        Action::Continue
    }
}

