#!/usr/bin/env bash

if [[ $1 == "--config" ]] ; then
  cat <<EOF
configVersion: v1
kubernetes:
- apiVersion: v1
  kind: Pod
  executeHookOnEvent:
  - Added
  - Modified
  - Deleted
  labelSelector:
    matchLabels:
      app: traefik
  namespace:
    nameSelector:
      matchNames:
      - traefik
EOF

else
  podName=$(jq -r .[0].object.metadata.name $BINDING_CONTEXT_PATH)
  eventType=$(jq -r .[0].type $BINDING_CONTEXT_PATH)
  
  echo "Pod ${podName} ${eventType}"
fi