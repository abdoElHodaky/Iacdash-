# 📚 Technical Glossary

Comprehensive glossary of terms, concepts, and technologies used in this Gateway API and Service Mesh infrastructure platform.

---

## 🏗️ **Infrastructure & Platform**

### **Infrastructure as Code (IaC)**
Declarative approach to infrastructure management using code files (Terraform, CloudFormation) instead of manual configuration. Enables version control, reproducibility, and automation.

### **GitOps**
Operational framework using Git as the single source of truth for declarative infrastructure and applications. Changes are made via Git commits and automatically applied by operators like FluxCD.

### **FluxCD**
Kubernetes-native GitOps operator that automatically synchronizes cluster state with Git repositories. Supports Helm charts, Kustomize, and plain Kubernetes manifests.

### **Terraform**
Infrastructure as Code tool for building, changing, and versioning infrastructure across multiple cloud providers using declarative configuration files.

### **Helm**
Package manager for Kubernetes that uses charts (packages) to define, install, and upgrade complex Kubernetes applications.

### **Kustomize**
Kubernetes-native configuration management tool that customizes YAML configurations without templates using overlays and patches.

---

## 🌐 **Networking & Gateway API**

### **Gateway API**
Next-generation Kubernetes ingress API providing role-oriented, expressive, and extensible traffic management. Successor to Ingress API with better separation of concerns.

### **GatewayClass**
Cluster-scoped resource defining the controller implementation (Istio, Envoy, Kong) that will handle Gateway resources. Managed by infrastructure operators.

### **Gateway**
Namespaced resource representing a load balancer with listeners for different protocols (HTTP, HTTPS, TCP, UDP). Managed by cluster operators.

### **HTTPRoute**
Resource defining HTTP traffic routing rules, including path matching, header manipulation, and traffic splitting. Managed by application developers.

### **TLS Termination**
Process of decrypting TLS/SSL traffic at the load balancer or gateway, allowing inspection and routing of plain HTTP traffic to backend services.

### **Traffic Splitting**
Technique for distributing incoming requests across multiple backend services based on weights, enabling canary deployments and A/B testing.

---

## 🕸️ **Service Mesh & Istio**

### **Service Mesh**
Infrastructure layer providing service-to-service communication, security, observability, and traffic management without requiring application code changes.

### **Istio**
Open-source service mesh platform providing traffic management, security, and observability for microservices using Envoy proxy sidecars.

### **Envoy Proxy**
High-performance proxy used as the data plane in Istio, handling all network traffic between services with advanced load balancing and observability features.

### **Sidecar Pattern**
Deployment pattern where Envoy proxy runs alongside each application container, intercepting and managing all network traffic.

### **Virtual Service**
Istio resource defining traffic routing rules, including request matching, traffic splitting, fault injection, and timeout configuration.

### **Destination Rule**
Istio resource defining policies for traffic to a service, including load balancing, connection pooling, and circuit breaker settings.

### **mTLS (Mutual TLS)**
Security protocol where both client and server authenticate each other using certificates, providing encryption and identity verification.

### **RBAC (Role-Based Access Control)**
Security model controlling access to resources based on user roles and permissions, implemented in Kubernetes and Istio.

---

## 🔐 **Security & Certificates**

### **cert-manager**
Kubernetes operator that automatically provisions and manages TLS certificates from various sources including Let's Encrypt, HashiCorp Vault, and self-signed CAs.

### **Let's Encrypt**
Free, automated Certificate Authority providing TLS certificates with automated issuance and renewal using ACME protocol.

### **ACME Protocol**
Automated Certificate Management Environment protocol for automated certificate issuance and validation, used by Let's Encrypt.

### **External Secrets Operator**
Kubernetes operator that synchronizes secrets from external systems (AWS Secrets Manager, HashiCorp Vault, Azure Key Vault) into Kubernetes secrets.

### **IRSA (IAM Roles for Service Accounts)**
AWS feature allowing Kubernetes service accounts to assume IAM roles, providing secure access to AWS services without storing credentials.

### **Workload Identity**
Google Cloud feature allowing Kubernetes service accounts to act as Google Cloud service accounts for secure access to GCP services.

### **Zero Trust**
Security model assuming no implicit trust, requiring verification for every access request regardless of location or user credentials.

---

## 📊 **Observability & Monitoring**

### **Observability**
Practice of understanding system internal state through external outputs, comprising three pillars: metrics, logs, and traces.

### **Prometheus**
Open-source monitoring system collecting metrics from configured targets at given intervals, evaluating rule expressions, and triggering alerts.

### **Grafana**
Open-source analytics and monitoring platform for visualizing metrics, logs, and traces from various data sources including Prometheus.

### **Loki**
Horizontally scalable log aggregation system inspired by Prometheus, designed for storing and querying logs efficiently.

### **Tempo**
Open-source distributed tracing backend supporting multiple trace formats including Jaeger, Zipkin, and OpenTelemetry.

### **OpenTelemetry**
Observability framework providing APIs, libraries, and instrumentation for collecting metrics, logs, and traces from applications.

### **Jaeger**
Distributed tracing platform for monitoring and troubleshooting microservices-based distributed systems.

### **SLI (Service Level Indicator)**
Quantitative measure of service level, such as request latency, error rate, or system throughput.

### **SLO (Service Level Objective)**
Target value or range for SLIs, defining acceptable service performance levels.

### **Error Budget**
Amount of unreliability permitted within SLOs, calculated as (100% - SLO percentage) × time period.

### **Burn Rate**
Rate at which error budget is consumed, used for alerting on SLO violations.

---

## 🚀 **Deployment & Automation**

### **Progressive Delivery**
Deployment strategy gradually rolling out changes to reduce risk, including techniques like canary deployments, blue-green deployments, and feature flags.

### **Canary Deployment**
Deployment strategy releasing changes to a small subset of users before full rollout, allowing early detection of issues.

### **Blue-Green Deployment**
Deployment strategy maintaining two identical production environments, switching traffic between them for zero-downtime deployments.

### **Flagger**
Progressive delivery operator for Kubernetes, automating canary deployments and A/B testing with traffic shifting and automated rollbacks.

### **Feature Flags**
Technique for toggling features on/off without code deployment, enabling controlled feature rollouts and A/B testing.

### **Circuit Breaker**
Design pattern preventing cascading failures by monitoring service health and temporarily blocking requests to failing services.

---

## 🔧 **Development & Operations**

### **WASM (WebAssembly)**
Binary instruction format enabling high-performance execution of code in web browsers and other environments, used for Envoy proxy extensions.

### **OPA (Open Policy Agent)**
Policy engine enabling unified policy enforcement across the stack, commonly used for Kubernetes admission control and authorization.

### **Gatekeeper**
Kubernetes admission controller using OPA for policy enforcement, validating and mutating resources based on defined policies.

### **CRD (Custom Resource Definition)**
Kubernetes extension mechanism allowing definition of custom resources with their own API endpoints and controllers.

### **Operator Pattern**
Kubernetes pattern for packaging, deploying, and managing applications using custom controllers that extend Kubernetes API.

### **Admission Controller**
Kubernetes component intercepting API requests after authentication and authorization but before persistence, enabling validation and mutation.

---

## ☁️ **Cloud & Infrastructure**

### **Multi-Cloud**
Strategy using multiple cloud providers to avoid vendor lock-in, improve resilience, and optimize costs across different services.

### **Hybrid Cloud**
Computing environment combining on-premises infrastructure with public cloud services, connected through orchestration and management tools.

### **Kubernetes**
Open-source container orchestration platform automating deployment, scaling, and management of containerized applications.

### **Container**
Lightweight, portable package containing application code, runtime, system tools, and libraries, ensuring consistent execution across environments.

### **Pod**
Smallest deployable unit in Kubernetes, containing one or more containers sharing network and storage resources.

### **Namespace**
Kubernetes mechanism for isolating groups of resources within a cluster, providing scope for names and enabling resource quotas.

---

## 📈 **Performance & Scaling**

### **Horizontal Pod Autoscaler (HPA)**
Kubernetes controller automatically scaling the number of pods based on CPU utilization, memory usage, or custom metrics.

### **Vertical Pod Autoscaler (VPA)**
Kubernetes controller automatically adjusting CPU and memory requests/limits for containers based on historical usage.

### **Load Balancing**
Technique distributing incoming requests across multiple backend servers to optimize resource utilization and prevent overload.

### **Rate Limiting**
Technique controlling the rate of requests to prevent system overload and ensure fair resource usage among clients.

### **Caching**
Technique storing frequently accessed data in fast storage to reduce latency and backend load.

---

## 🔄 **Data & Storage**

### **Persistent Volume (PV)**
Kubernetes storage resource representing a piece of storage in the cluster, independent of pod lifecycle.

### **Persistent Volume Claim (PVC)**
Kubernetes request for storage by a user, binding to available persistent volumes based on size and access mode requirements.

### **Storage Class**
Kubernetes resource defining different types of storage with specific parameters, enabling dynamic provisioning of persistent volumes.

### **Backup**
Process of creating copies of data and configurations to enable recovery in case of data loss or system failure.

### **Disaster Recovery**
Strategies and procedures for recovering IT infrastructure and operations after catastrophic events.

---

## 🏷️ **Naming & Conventions**

### **Labels**
Key-value pairs attached to Kubernetes objects for identification and selection, used by selectors and controllers.

### **Annotations**
Key-value pairs attached to Kubernetes objects for storing non-identifying metadata, used by tools and libraries.

### **Selectors**
Kubernetes mechanism for identifying and grouping objects based on labels, used by services, deployments, and other controllers.

### **Tagging Strategy**
Systematic approach to applying metadata tags to cloud resources for organization, cost tracking, and automation.

---

## 🔍 **Troubleshooting & Debugging**

### **Health Check**
Automated test determining if a service or component is functioning correctly, used for load balancing and monitoring decisions.

### **Readiness Probe**
Kubernetes mechanism determining if a container is ready to accept traffic, used by services for routing decisions.

### **Liveness Probe**
Kubernetes mechanism determining if a container is running correctly, triggering restarts when checks fail.

### **Debug Mode**
Operational mode providing additional logging, metrics, and diagnostic information for troubleshooting issues.

### **Distributed Tracing**
Method of tracking requests across multiple services in distributed systems, providing visibility into request flow and performance.

---

## 📝 **Configuration Management**

### **ConfigMap**
Kubernetes object storing non-confidential configuration data in key-value pairs, consumed by pods as environment variables or files.

### **Secret**
Kubernetes object storing sensitive information like passwords, tokens, and keys, with base64 encoding and optional encryption at rest.

### **Environment Variables**
Dynamic values passed to containers at runtime, used for configuration without rebuilding container images.

### **Immutable Infrastructure**
Practice of replacing infrastructure components rather than modifying them, ensuring consistency and reducing configuration drift.

---

This glossary serves as a reference for understanding the technologies, patterns, and practices implemented in this platform. For detailed implementation examples, refer to the specific documentation files and configuration examples throughout the repository.

