# Prometheus file_sd targets

This folder contains `file_sd` target groups used by `prometheus.yml`.

- `microservices.json`: sample targets for the companion repos (microservices + saga).

In production (Kubernetes), prefer Kubernetes service discovery instead of file_sd.
