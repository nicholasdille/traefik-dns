#!/bin/bash

# TODO: argument parsing
#       - use default kubeconfig
#       - use specific file
#       - (default) use service account in container
CONTEXT="svc-3-admin"
#       - what to watch (namespace, label selector)
NAMESPACE="gocd-qa"
LABEL_SELECTOR="service=gocd"
#       - what to update (name of DNSEndpoint)
DNSENDPOINT_NAME=traefik-dns
#       - log level

# TODO: Check availability of kubectl, curl, jq
for tool in kubectl curl jq; do
    if ! type ${tool} >/dev/null 2>&1; then
        echo "ERROR: I need ${tool} to work."
        exit 1
    fi
done

# TODO: Create kubeconfig

# TODO: Check availability of DNSEndpoint
if ! kubectl get crd dnsendpoints.externaldns.k8s.io >/dev/null 2>&1; then
    echo "ERROR: I need external-dns running in the cluster."
    exit 1
fi

function cleanup() {
    echo "INFO: Cleaning up..."
    test -n "${KUBECTL_PROXY_PID}" && kill ${KUBECTL_PROXY_PID}
    echo "INFO: Goodbye!"
}
trap cleanup EXIT

function start_api_proxy() {
    echo "INFO: Setting up kubectl proxy..."
    kubectl --context=${CONTEXT} proxy &
    KUBECTL_PROXY_PID=$!
    echo "DEBUG: kubectl proxy running with PID ${KUBECTL_PROXY_PID}."
    MAX_ATTEMPTS=5
    ATTEMPT=1
    while test "${ATTEMPT}" -le 5 && ! timeout 1 bash -c 'cat </dev/null >/dev/tcp/localhost/8001 2>/dev/null'; do
        echo "DEBUG: Waiting for kubectl proxy to start..."
        sleep 1
    done
    if ! timeout 1 bash -c 'cat < /dev/null > /dev/tcp/localhost/8001'; then
        echo "ERROR: kubectl proxy not working."
        exit 1
    fi
}

function watch_using_api_proxy() {
    echo "INFO: Watching events for pods in namespace ${NAMESPACE} with labels ${LABEL_SELECTOR}..."
    curl --silent "http://localhost:8001/api/v1/namespaces/${NAMESPACE}/pods?labelSelector=${LABEL_SELECTOR}&watch=true" | \
        while read; do
            echo ${EVENT}
        done
}

current_pod_name=""
current_pod_state=""
candidate_pod_name=""
candidate_pod_state=""
kubectl --context ${CONTEXT} --namespace ${NAMESPACE} get pods --selector ${LABEL_SELECTOR} --watch --output-watch-events --output json | \
    while read EVENT; do
        event_type=$(echo ${EVENT} | jq --raw-output '.type')

        resource_name=$(echo ${EVENT} | jq --raw-output '.object.metadata.name')
        resource_phase=$(echo ${EVENT} | jq --raw-output '.object.status.phase')
        if test "${resource_phase}" == "Running" && test "$(echo ${EVENT} | jq --raw-output '.object.status.containerStatuses[].state | to_entries[].key' | uniq | wc -l)" -eq 1; then
            resource_state=$(echo ${EVENT} | jq --raw-output '.object.status.containerStatuses[].state | to_entries[].key' | uniq)
        fi
        
        echo "Debug: Got event with type=${event_type}, resource_name=${resource_name}, resource_state=${resource_state}."

        case "${event_type}" in
            ADDED)
                if test -z "${current_pod_name}"; then
                    current_pod_name=${resource_name}
                    current_pod_state=${resource_state}
                    echo "DEBUG: Following pod ${current_pod_name} (${current_pod_state})."

                elif test "${resource_name}" == "${current_pod_name}"; then
                    current_pod_state=${resource_state}
                    echo "DEBUG: New state for current pod ${current_pod_name} (${current_pod_state})."

                elif test -z "${candidate_pod_name}"; then
                    candidate_pod_name=${resource_name}
                    candidate_pod_state=${resource_state}
                    echo "DEBUG: Following candidate pod ${candidate_pod_name} (${candidate_pod_state})."

                elif test "${resource_name}" == "${candidate_pod_name}"; then
                    candidate_pod_state=${resource_state}
                    echo "DEBUG: New state for candidate pod ${candidate_pod_name} (${candidate_pod_state})."
                fi
            ;;
            MODIFIED)
                if test "${resource_name}" == "${current_pod_name}"; then
                    current_pod_state=${resource_state}
                    echo "DEBUG: New state for current pod ${current_pod_name} (${current_pod_state})."

                elif test "${resource_name}" == "${candidate_pod_name}"; then
                    candidate_pod_state=${resource_state}
                    echo "DEBUG: New state for candidate pod ${candidate_pod_name} (${candidate_pod_state})."
                fi
            ;;
            DELETED)
                if test "${resource_name}" == "${current_pod_name}"; then
                    echo "DEBUG: Processing deletion for current pod ${current_pod_name}."
                    if test -n "${candidate_pod_name}"; then
                        current_pod_name=${candidate_pod_name}
                        current_pod_state=${candidate_pod_state}
                        echo "DEBUG: Switching to candidate pod ${candidate_pod_name} (${candidate_pod_state})."
                    
                    else
                        echo "DEBUG: No candidate evailable. Unable to switch."
                    fi
                fi
            ;;
        esac

        echo "DEBUG: Done with event."
    done