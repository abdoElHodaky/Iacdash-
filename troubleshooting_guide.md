# 🔧 Troubleshooting Guide

Complete guide for debugging Gateway API, Service Mesh, and infrastructure issues.

---

## 📋 Table of Contents

- [Quick Diagnosis](#quick-diagnosis)
- [Gateway API Issues](#gateway-api-issues)
- [Service Mesh Problems](#service-mesh-problems)
- [Network Issues](#network-issues)
- [FluxCD Troubleshooting](#fluxcd-troubleshooting)
- [Performance Problems](#performance-problems)
- [Certificate Issues](#certificate-issues)
- [Common Error Messages](#common-error-messages)
- [Debug Commands](#debug-commands)

---

## Quick Diagnosis

### Health Check Script

```bash
#!/bin/bash
# health-check.sh

echo "=== Kubernetes Cluster ==="
kubectl cluster-info
kubectl get nodes

echo -e "\n=== Gateway API ==="
kubectl get gatewayclasses
kubectl get gateways -A
kubectl get httproutes -A

echo -e "\n=== Service Mesh ==="
kubectl get pods -n istio-system
# or: kubectl get pods -n linkerd

echo -e "\n=== Monitoring ==="
kubectl get pods -n monitoring

echo -e "\n=== FluxCD ==="
flux check
flux get all -A

echo -e "\n=== Failed Pods ==="
kubectl get pods -A | grep -v "Running\|Completed"
```

### Quick Fixes Checklist

- [ ] Are all pods running? `kubectl get pods -A`
- [ ] Is the gateway accepting traffic? `kubectl get gateway`
- [ ] Are routes attached to gateway? `kubectl describe httproute`
- [ ] Is mTLS working? `istioctl authn tls-check`
- [ ] Are certificates valid? `kubectl get certificates -A`
- [ ] Is FluxCD reconciling? `flux get kustomizations`
- [ ] Are metrics being collected? Check Prometheus targets
- [ ] Are there network policy issues? Check NetworkPolicy

---

## Gateway API Issues

### Problem: Gateway Not Ready

**Symptoms:**
- Gateway status shows `Programmed: False`
- Routes not accepting traffic
- `kubectl get gateway` shows no addresses

**Diagnosis:**

```bash
# Check gateway status
kubectl get gateway production-gateway -o yaml

# Check gateway controller logs
kubectl logs -n istio-system -l app=istio-ingressgateway --tail=100

# Verify GatewayClass exists
kubectl get gatewayclass

# Check for events
kubectl describe gateway production-gateway
```

**Common Causes & Solutions:**

1. **GatewayClass not found**
   ```bash
   # Create GatewayClass
   kubectl apply -f - <<EOF
   apiVersion: gateway.networking.k8s.io/v1
   kind: GatewayClass
   metadata:
     name: istio
   spec:
     controllerName: istio.io/gateway-controller
   EOF
   ```

2. **Missing controller**
   ```bash
   # Verify Istio is installed
   kubectl get pods -n istio-system
   
   # Reinstall if needed
   istioctl install --set profile=default -y
   ```

3. **LoadBalancer pending**
   ```bash
   # Check service
   kubectl get svc -n istio-system istio-ingressgateway
   
   # For cloud providers, verify quotas
   # For local (KinD), use NodePort or port-forward
   ```

### Problem: HTTPRoute Not Working

**Symptoms:**
- Route shows `Accepted: False`
- Traffic not reaching backend
- 404 errors

**Diagnosis:**

```bash
# Check route status
kubectl get httproute api-route -o yaml

# Verify backend service exists
kubectl get svc backend-service

# Check route attachment
kubectl describe httproute api-route

# Test from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://backend-service.default.svc.cluster.local
```

**Solutions:**

1. **Backend service doesn't exist**
   ```bash
   # Verify service
   kubectl get svc backend-service
   kubectl get endpoints backend-service
   
   # Create if missing
   kubectl expose deployment backend --port=8080
   ```

2. **Route not attached to gateway**
   ```yaml
   # Fix parentRefs
   spec:
     parentRefs:
     - name: production-gateway
       namespace: default  # Add if cross-namespace
   ```

3. **Hostname mismatch**
   ```bash
   # Test with correct hostname
   curl -H "Host: api.example.com" http://gateway-ip/path
   ```

### Problem: TLS Not Working

**Symptoms:**
- Certificate errors
- TLS handshake failures
- `ERR_CERT_AUTHORITY_INVALID`

**Diagnosis:**

```bash
# Check certificate
kubectl get certificate -A
kubectl describe certificate wildcard-tls

# Check secret
kubectl get secret wildcard-tls -o yaml

# Test TLS
openssl s_client -connect api.example.com:443 -servername api.example.com

# Check cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager
```

**Solutions:**

1. **Certificate not ready**
   ```bash
   # Check cert-manager status
   kubectl get certificaterequests -A
   kubectl describe certificaterequest <name>
   
   # Force renewal
   kubectl delete certificaterequest <name>
   ```

2. **Wrong issuer**
   ```yaml
   # Use correct issuer
   metadata:
     annotations:
       cert-manager.io/cluster-issuer: "letsencrypt-prod"
   ```

3. **DNS validation failing**
   ```bash
   # Check DNS records
   dig api.example.com
   
   # Verify ACME challenge
   kubectl get challenges -A
   kubectl describe challenge <name>
   ```

---

## Service Mesh Problems

### Problem: mTLS Not Working

**Symptoms:**
- Connection refused
- TLS handshake errors
- Services can't communicate

**Diagnosis:**

```bash
# Check mTLS status (Istio)
istioctl authn tls-check pod-name.namespace

# Check PeerAuthentication
kubectl get peerauthentication -A

# View proxy configuration
istioctl proxy-config secret pod-name.namespace

# Check for mTLS in logs
kubectl logs pod-name -c istio-proxy
```

**Solutions:**

1. **Mixed PERMISSIVE/STRICT mode**
   ```yaml
   # Set consistent mode
   apiVersion: security.istio.io/v1beta1
   kind: PeerAuthentication
   metadata:
     name: default
     namespace: istio-system
   spec:
     mtls:
       mode: STRICT
   ```

2. **Sidecar not injected**
   ```bash
   # Check injection
   kubectl get pod pod-name -o yaml | grep istio-proxy
   
   # Label namespace
   kubectl label namespace default istio-injection=enabled
   
   # Restart pods
   kubectl rollout restart deployment/app-name
   ```

3. **Certificate issues**
   ```bash
   # Check certificate rotation
   istioctl proxy-config secret pod-name.namespace -o json | jq '.dynamicActiveSecrets'
   
   # Restart istiod if needed
   kubectl rollout restart deployment/istiod -n istio-system
   ```

### Problem: Traffic Not Routing Correctly

**Symptoms:**
- Wrong service version receiving traffic
- Canary not working
- Load balancing issues

**Diagnosis:**

```bash
# Check VirtualService
kubectl get virtualservice -A
kubectl describe virtualservice api-service

# Check DestinationRule
kubectl get destinationrule -A
kubectl describe destinationrule api-service

# View Envoy configuration
istioctl proxy-config routes pod-name.namespace

# Check subset labels
kubectl get pods -L version
```

**Solutions:**

1. **Subset labels don't match**
   ```yaml
   # Fix labels in DestinationRule
   subsets:
   - name: v1
     labels:
       version: v1  # Must match pod labels
   ```

2. **Conflicting VirtualServices**
   ```bash
   # Check for conflicts
   kubectl get virtualservice -A -o yaml | grep -A 5 "host: api-service"
   
   # Remove or consolidate duplicates
   ```

3. **Weight not adding to 100**
   ```yaml
   # Fix weights
   route:
   - destination:
       host: api-service
       subset: v1
     weight: 90
   - destination:
       host: api-service
       subset: v2
     weight: 10  # Must total 100
   ```

### Problem: Circuit Breaker Not Triggering

**Symptoms:**
- No connection pooling
- All requests reaching backend
- No outlier detection

**Diagnosis:**

```bash
# Check DestinationRule
kubectl get destinationrule api-service -o yaml

# View connection pool stats
istioctl proxy-config clusters pod-name.namespace --fqdn api-service.default.svc.cluster.local

# Check Envoy stats
kubectl exec pod-name -c istio-proxy -- curl localhost:15000/stats | grep outlier
```

**Solutions:**

```yaml
# Ensure circuit breaker is properly configured
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: api-service
spec:
  host: api-service
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 10
        maxRequestsPerConnection: 2
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
```

---

## Network Issues

### Problem: Pods Can't Communicate

**Symptoms:**
- Connection timeout
- `No route to host`
- DNS resolution failures

**Diagnosis:**

```bash
# Test DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup backend-service.default.svc.cluster.local

# Test connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://backend-service.default.svc.cluster.local:8080

# Check NetworkPolicies
kubectl get networkpolicy -A
kubectl describe networkpolicy default-deny

# Check service endpoints
kubectl get endpoints backend-service
```

**Solutions:**

1. **NetworkPolicy blocking traffic**
   ```bash
   # Temporarily remove policies to test
   kubectl delete networkpolicy --all -n default
   
   # Add allow rule
   kubectl apply -f - <<EOF
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-from-frontend
     namespace: default
   spec:
     podSelector:
       matchLabels:
         app: backend
     ingress:
     - from:
       - podSelector:
           matchLabels:
             app: frontend
   EOF
   ```

2. **Service selector mismatch**
   ```bash
   # Check service selector
   kubectl get svc backend-service -o yaml | grep -A 5 selector
   
   # Check pod labels
   kubectl get pods -L app
   
   # Fix if they don't match
   ```

3. **DNS issues**
   ```bash
   # Check CoreDNS
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   kubectl logs -n kube-system -l k8s-app=kube-dns
   
   # Restart CoreDNS
   kubectl rollout restart deployment/coredns -n kube-system
   ```

### Problem: External Traffic Not Reaching Cluster

**Symptoms:**
- Gateway timeout
- Can't access from outside
- LoadBalancer has no external IP

**Diagnosis:**

```bash
# Check ingress gateway service
kubectl get svc -n istio-system istio-ingressgateway

# Check for external IP
GATEWAY_IP=$(kubectl get svc -n istio-system istio-ingressgateway \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $GATEWAY_IP

# Test from outside
curl -v http://$GATEWAY_IP

# Check firewall rules (cloud provider)
# GCP: gcloud compute firewall-rules list
# AWS: aws ec2 describe-security-groups
```

**Solutions:**

1. **LoadBalancer stuck pending**
   ```bash
   # For KinD, use port-forward
   kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
   
   # For cloud, check quotas and permissions
   ```

2. **Firewall blocking traffic**
   ```bash
   # Allow ports 80 and 443
   # GCP example:
   gcloud compute firewall-rules create allow-gateway \
     --allow tcp:80,tcp:443 \
     --source-ranges 0.0.0.0/0 \
     --target-tags=gke-node
   ```

---

## FluxCD Troubleshooting

### Problem: Reconciliation Failing

**Symptoms:**
- `flux get all` shows errors
- Resources not applying
- Git sync issues

**Diagnosis:**

```bash
# Check Flux status
flux check
flux get all -A

# View events
flux events --for Kustomization/infrastructure

# Check logs
flux logs --level=error

# Specific resource
kubectl describe kustomization infrastructure -n flux-system
```

**Solutions:**

1. **Git authentication failure**
   ```bash
   # Recreate secret
   flux create secret git flux-system \
     --url=https://github.com/org/repo \
     --username=git \
     --password=$GITHUB_TOKEN
   
   # Or use SSH
   flux bootstrap github \
     --owner=org \
     --repository=repo \
     --path=clusters/production
   ```

2. **Invalid manifests**
   ```bash
   # Validate locally
   flux build kustomization infrastructure \
     --path ./infrastructure
   
   # Check YAML syntax
   kubectl apply --dry-run=client -f infrastructure/
   ```

3. **Dependency issues**
   ```yaml
   # Fix dependencies
   spec:
     dependsOn:
     - name: infrastructure
       namespace: flux-system
   ```

### Problem: HelmRelease Failing

**Symptoms:**
- Helm chart not installing
- Upgrade failures
- Rollback errors

**Diagnosis:**

```bash
# Check HelmRelease
flux get helmreleases -A

# View events
kubectl describe helmrelease prometheus -n monitoring

# Check Helm logs
kubectl logs -n flux-system deploy/helm-controller
```

**Solutions:**

1. **Values file errors**
   ```bash
   # Validate values
   helm template prometheus prometheus-community/kube-prometheus-stack \
     --values values.yaml \
     --debug
   ```

2. **Chart version mismatch**
   ```yaml
   # Pin to specific version
   spec:
     chart:
       spec:
         version: "55.0.0"  # Don't use ranges in production
   ```

---

## Performance Problems

### Problem: High Latency

**Symptoms:**
- Slow response times
- P95 latency > 1s
- Timeout errors

**Diagnosis:**

```bash
# Check proxy stats
istioctl proxy-config clusters pod-name.namespace

# View metrics in Prometheus
# P95 latency
histogram_quantile(0.95, 
  sum(rate(istio_request_duration_milliseconds_bucket[5m])) by (le)
)

# Check resource usage
kubectl top pods
kubectl top nodes

# Trace request
# Use Jaeger/Kiali to view distributed trace
```

**Solutions:**

1. **Resource limits too low**
   ```yaml
   # Increase resources
   resources:
     requests:
       cpu: 500m
       memory: 512Mi
     limits:
       cpu: 2000m
       memory: 2048Mi
   ```

2. **Too many retries**
   ```yaml
   # Reduce retry attempts
   retries:
     attempts: 2  # Down from 3
     perTryTimeout: 1s  # Down from 2s
   ```

3. **Connection pool exhausted**
   ```yaml
   # Increase pool size
   trafficPolicy:
     connectionPool:
       tcp:
         maxConnections: 200  # Up from 100
       http:
         http2MaxRequests: 200  # Up from 100
   ```

### Problem: High Memory Usage

**Symptoms:**
- Pods being OOMKilled
- Memory usage constantly high
- Frequent restarts

**Diagnosis:**

```bash
# Check memory usage
kubectl top pods

# View OOMKills
kubectl get pods -o json | jq '.items[] | select(.status.containerStatuses[]?.lastState.terminated.reason=="OOMKilled")'

# Check limits
kubectl describe pod pod-name | grep -A 5 Limits
```

**Solutions:**

1. **Memory leak**
   ```bash
   # Profile application
   # Check for memory leaks in code
   
   # Temporary: increase memory
   # Permanent: fix application code
   ```

2. **Limits too restrictive**
   ```yaml
   # Increase memory limits
   resources:
     limits:
       memory: 2Gi  # Up from 1Gi
   ```

---

## Certificate Issues

### Problem: Certificate Not Renewing

**Symptoms:**
- Certificate expired
- `ERR_CERT_DATE_INVALID`
- cert-manager errors

**Diagnosis:**

```bash
# Check certificate
kubectl get certificate -A
kubectl describe certificate wildcard-tls

# Check cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager

# Check challenges
kubectl get challenges -A
kubectl describe challenge <name>
```

**Solutions:**

1. **ACME challenge failing**
   ```bash
   # Check ingress for challenge
   kubectl get ingress -A
   
   # Verify DNS
   dig _acme-challenge.example.com TXT
   
   # Delete and recreate certificate
   kubectl delete certificate wildcard-tls
   kubectl apply -f certificate.yaml
   ```

2. **Rate limit hit**
   ```bash
   # Use staging issuer temporarily
   # letsencrypt-staging has higher rate limits
   
   # Wait for rate limit to reset (1 week)
   ```

---

## Common Error Messages

### "no healthy upstream"

**Cause:** Backend pods not ready or endpoints not found

**Solution:**
```bash
kubectl get pods -l app=backend
kubectl get endpoints backend-service
kubectl describe pod <pod-name>
```

### "upstream connect error or disconnect/reset before headers"

**Cause:** Backend service crashed or connection pool exhausted

**Solution:**
```bash
# Check backend logs
kubectl logs <pod-name>

# Increase connection pool
# See DestinationRule configuration above
```

### "RBAC: access denied"

**Cause:** Insufficient permissions

**Solution:**
```bash
# Check permissions
kubectl auth can-i get pods --as=system:serviceaccount:default:api-service

# Update RBAC
kubectl apply -f rbac.yaml
```

---

## Debug Commands

### Essential Debug Commands

```bash
# Gateway API
kubectl api-resources | grep gateway
kubectl get gateways,httproutes -A -o wide
kubectl describe gateway <name>
kubectl get gateway <name> -o yaml

# Service Mesh (Istio)
istioctl version
istioctl proxy-status
istioctl analyze
istioctl dashboard kiali
istioctl proxy-config routes <pod>
istioctl proxy-config clusters <pod>

# Service Mesh (Linkerd)
linkerd check
linkerd viz stat deploy
linkerd viz top deploy
linkerd viz tap deploy/<name>

# Networking
kubectl get svc,endpoints -A
kubectl get networkpolicies -A
kubectl run debug --rm -it --image=nicolaka/netshoot

# FluxCD
flux check
flux get all -A
flux logs --level=error
flux reconcile kustomization <name> --with-source

# Monitoring
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Logs
kubectl logs <pod> --all-containers
kubectl logs <pod> -c istio-proxy
kubectl logs <pod> --previous

# Events
kubectl get events -A --sort-by='.lastTimestamp'
kubectl describe pod <pod-name>
```

### Interactive Debugging

```bash
# Shell into pod
kubectl exec -it <pod-name> -- /bin/sh

# Shell into istio-proxy
kubectl exec -it <pod-name> -c istio-proxy -- /bin/bash

# Port forward to local
kubectl port-forward pod/<pod-name> 8080:8080

# Temporary debug pod
kubectl run debug --rm -it --image=busybox -- /bin/sh
kubectl run debug --rm -it --image=curlimages/curl -- sh
kubectl run debug --rm -it --image=nicolaka/netshoot -- /bin/bash
```

---

## Getting Help

### Before Opening an Issue

1. ✅ Checked this troubleshooting guide
2. ✅ Reviewed logs for errors
3. ✅ Verified configuration syntax
4. ✅ Tested in isolation (minimal config)
5. ✅ Gathered relevant information:
   - Kubernetes version: `kubectl version`
   - Gateway API version: `kubectl api-resources | grep gateway`
   - Service mesh version: `istioctl version` or `linkerd version`
   - Error messages and logs
   - Configuration files (redacted)

### Community Resources

- **Gateway API**: https://github.com/kubernetes-sigs/gateway-api
- **Istio**: https://discuss.istio.io/
- **Linkerd**: https://linkerd.io/community/
- **FluxCD**: https://fluxcd.io/#community
- **Kubernetes**: https://kubernetes.slack.com/

---

**💡 Tip:** Most issues are caused by configuration errors, missing resources, or permission problems. Start with the basics: verify resources exist, check logs, and validate YAML syntax.