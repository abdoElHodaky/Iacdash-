# Gateway API Authorization Policy
# This policy defines authorization rules for Gateway API resources

package gateway.authz

# Default deny - all requests are denied unless explicitly allowed
default allow = false

# Allow requests that pass all authorization checks
allow {
    valid_token
    valid_path
    valid_method
    rate_limit_check
}

# Token validation
valid_token {
    # Extract token from Authorization header
    token := extract_token(input.attributes.request.http.headers.authorization)
    
    # Validate token format (simplified - in production use proper JWT validation)
    count(token) > 10
    
    # Check token against allowed patterns
    regex.match("^[A-Za-z0-9_-]+$", token)
}

# Path validation
valid_path {
    path := input.attributes.request.http.path
    
    # Allow health check endpoints
    startswith(path, "/health")
}

valid_path {
    path := input.attributes.request.http.path
    
    # Allow API endpoints with proper versioning
    regex.match("^/api/v[0-9]+/", path)
    
    # Ensure no path traversal attempts
    not contains(path, "..")
    not contains(path, "//")
}

valid_path {
    path := input.attributes.request.http.path
    
    # Allow static content
    startswith(path, "/static/")
    
    # Only allow safe file extensions
    allowed_extensions := {".css", ".js", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico"}
    # Simple check for file extensions
    some ext
    allowed_extensions[ext]
    endswith(path, ext)
}

# Method validation
valid_method {
    method := input.attributes.request.http.method
    {"GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"}[method]
}

# Rate limiting check (simplified)
rate_limit_check {
    # Get client identifier
    client_ip := get_client_ip
    
    # In a real implementation, this would check against a rate limiting service
    # For now, we'll allow all requests that have made it this far
    true
}

# Helper functions
extract_token(auth_header) := token {
    auth_header
    startswith(auth_header, "Bearer ")
    token := substring(auth_header, 7, -1)
}

extract_token(auth_header) := "" {
    not auth_header
}

extract_token(auth_header) := "" {
    auth_header
    not startswith(auth_header, "Bearer ")
}

get_client_ip := ip {
    # Try X-Forwarded-For first
    forwarded := input.attributes.request.http.headers["x-forwarded-for"]
    forwarded
    ip := split(forwarded, ",")[0]
}

get_client_ip := ip {
    # Fall back to X-Real-IP
    not input.attributes.request.http.headers["x-forwarded-for"]
    ip := input.attributes.request.http.headers["x-real-ip"]
}

get_client_ip := ip {
    # Fall back to source IP
    not input.attributes.request.http.headers["x-forwarded-for"]
    not input.attributes.request.http.headers["x-real-ip"]
    ip := input.attributes.source.address.Address.SocketAddress.address
}

# Admin endpoints require special permissions
admin_access {
    path := input.attributes.request.http.path
    startswith(path, "/admin/")
    
    # Check for admin role in token claims (simplified)
    token := extract_token(input.attributes.request.http.headers.authorization)
    
    # In production, decode JWT and check roles
    # For demo, check for specific admin token pattern
    contains(token, "admin")
}

# Allow admin access only for admin endpoints
allow {
    path := input.attributes.request.http.path
    startswith(path, "/admin/")
    admin_access
}

# Deny admin endpoints for non-admin users
deny {
    path := input.attributes.request.http.path
    startswith(path, "/admin/")
    not admin_access
}

# Security headers enforcement
required_security_headers := {
    "x-content-type-options": "nosniff",
    "x-frame-options": "DENY",
    "x-xss-protection": "1; mode=block",
    "strict-transport-security": "max-age=31536000; includeSubDomains"
}

# Content type validation for POST/PUT requests
valid_content_type {
    method := input.attributes.request.http.method
    {"GET", "DELETE", "OPTIONS"}[method]
}

valid_content_type {
    method := input.attributes.request.http.method
    {"POST", "PUT", "PATCH"}[method]
    
    content_type := input.attributes.request.http.headers["content-type"]
    allowed_types := {
        "application/json",
        "application/x-www-form-urlencoded",
        "multipart/form-data",
        "text/plain"
    }
    
    # Check if content type starts with any allowed type
    some allowed_type
    allowed_types[allowed_type]
    startswith(content_type, allowed_type)
}

# Final authorization decision with content type check
allow {
    valid_token
    valid_path
    valid_method
    valid_content_type
    rate_limit_check
    not deny
}
