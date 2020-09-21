function k8s_event_get_type() {
    cat | jq --raw-output '.object.metadata.name'
}

function k8s_event_get_object_name() {
    cat | jq --raw-output '.object.status.phase'
}

function k8s_event_get_pod_states {
    cat | jq --raw-output '.object.status.containerStatuses[].state | to_entries[].key' | uniq
}