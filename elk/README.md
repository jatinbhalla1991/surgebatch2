# ELK Stack (Elasticsearch, Logstash, Kibana, Filebeat)

Self-contained logging stack for the sample app (`docker/docker-compose.yaml` /
`docker/menifest.yaml`). Kept in its own folder so it can be started independently
of the app it's collecting logs from.

Version: `8.15.0` across all components. `xpack.security.enabled=false` is set on
Elasticsearch/Kibana to keep this a quick-start/practice stack without TLS/cert
setup - don't reuse that setting as-is for anything production-facing.

## Local (Docker Compose)

Collects logs from every container in the Docker host (including the `web`,
`backend`, `db` services from `../docker/docker-compose.yaml`) via Filebeat's
Docker autodiscover, ships them through Logstash, and indexes them into
Elasticsearch.

```powershell
# start the sample app first so there's something to collect logs from
cd ..\docker
docker compose up -d

# then start the ELK stack
cd ..\elk
docker compose up -d
```

- Elasticsearch: http://localhost:9200
- Kibana: http://localhost:5601
- Logstash beats input: `localhost:5044`

In Kibana, create a data view for the `docker-logs-*` index pattern (Stack
Management > Data Views) to start browsing logs.

Config files:
- `logstash/pipeline/logstash.conf` - beats input -> optional nginx grok parsing -> Elasticsearch output
- `filebeat/filebeat.yml` - Docker autodiscover (hints-based, all containers)

## Kubernetes / AKS

Manifests in `k8s/` deploy the same stack into a `logging` namespace and use a
Filebeat DaemonSet (via Kubernetes autodiscover) to ship logs only from the
`sample` namespace defined in `../docker/menifest.yaml`.

```powershell
kubectl apply -f k8s\00-namespace.yaml
kubectl apply -f k8s\10-elasticsearch.yaml
kubectl apply -f k8s\20-logstash.yaml
kubectl apply -f k8s\30-kibana.yaml
kubectl apply -f k8s\40-filebeat.yaml
```

Elasticsearch uses an `emptyDir` volume (no storage-class dependency, but data
doesn't survive a pod restart) and Kibana is exposed via a `LoadBalancer`
`Service`, matching the pattern used for the sample app's `Service`. Swap
`emptyDir` for a `PersistentVolumeClaim` and/or `LoadBalancer` for `ClusterIP` +
`kubectl port-forward` as needed.

```powershell
kubectl get svc -n logging kibana   # grab the EXTERNAL-IP once provisioned
```
