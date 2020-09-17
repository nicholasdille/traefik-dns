# TODO: More verbose help for options
#       - valid parameters
function help() {
    cat <<EOF
Monitor traefik for restarts and use cert-manager to update DNS

$0 <options>

Options:
    --context, -c      Optional context to use from kubeconfig
    --namespace, -n    Namespace to watch pods in
    --selector, -l     Label selector to filter pods to watch
    --dnsendpoint      Name of the existing DNSEndpoint to update
    --loglevel         Optional verbosity of output (default: info)
    --help             This message

The environment variable KUBECONFIG is honoured.
EOF
}