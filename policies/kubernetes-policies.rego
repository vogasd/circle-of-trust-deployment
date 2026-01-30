package kubernetes.admission

deny[msg] {
    input.request.kind.kind == "Pod"
    image := input.request.object.spec.containers[_].image
    not startswith(image, "circlerecristry.azurecr.io/")
    msg := sprintf("Image '%v' does not come from approved registry", [image])
}

deny[msg] {
    input.request.kind.kind == "Pod"
    not input.request.object.spec.securityContext.runAsNonRoot
    msg := "Pods must run as non-root user"
}

deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not container.securityContext.readOnlyRootFilesystem
    msg := sprintf("Container '%v' must have read-only root filesystem", [container.name])
}

deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    container.securityContext.privileged
    msg := sprintf("Container '%v' cannot run in privileged mode", [container.name])
}

deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not container.resources.limits.cpu
    msg := sprintf("Container '%v' must have CPU limits", [container.name])
}

deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not container.resources.limits.memory
    msg := sprintf("Container '%v' must have memory limits", [container.name])
}

deny[msg] {
    input.request.kind.kind == "Service"
    input.request.object.spec.type == "LoadBalancer"
    not input.request.object.metadata.annotations["service.beta.kubernetes.io/azure-load-balancer-internal"]
    msg := "LoadBalancer services must be internal only"
}

deny[msg] {
    input.request.kind.kind == "Ingress"
    not input.request.object.spec.tls
    msg := "Ingress must have TLS configured"
}

warn[msg] {
    input.request.kind.kind == "Deployment"
    not input.request.object.spec.template.spec.affinity
    msg := "Deployment should have pod anti-affinity rules for high availability"
}

warn[msg] {
    input.request.kind.kind == "Deployment"
    input.request.object.spec.replicas < 2
    msg := "Deployment should have at least 2 replicas for high availability"
}
