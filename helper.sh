#!/bin/bash
set -o errexit

export DOCKER_BUILDKIT=1
docker build --tag nicholasdille/traefik-dns:latest .
docker push nicholasdille/traefik-dns:latest

kubectl -n traefik scale deployment traefik-dns --replicas=0
while test "$(kubectl -n traefik get pods -l app=traefik-dns | wc -l)" -gt 0; do
    sleep 1
done
kubectl apply -f deploy/