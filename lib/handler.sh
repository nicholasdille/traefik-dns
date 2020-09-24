function followed_pod_updated() {
    local selector=$1
    local name=$2

    IP=$(kubectl get pod ${name} -o json | jq --raw-output '.status.hostIP')
    verbose "Got host IP <${IP}> for pod <${name}>."
    if test -z "${IP}" || test "${IP}" == "null"; then
        error "Unable to determine host IP for pod <${name}>."

    else
        kubectl get dnsendpoint traefik-dns --output=yaml | \
            yq delete - 'spec.endpoints.(dnsName==traefik.go-nerd.de).targets' | \
            yq write - 'spec.endpoints.(dnsName==traefik.go-nerd.de).targets[+]' ${IP} | \
            kubectl apply -f -
        verbose "Target is now <$(kubectl get dnsendpoint traefik-dns -o json | jq --raw-output '.spec.endpoints[].targets[]')>."
    fi
}