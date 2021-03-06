local utils = import "lib/utils.libsonnet";
local inputs = std.extVar("inputs");

{
    _local:: {
        # imports go here, modify if version gets bumped
        # TODO: this would ideally be dependent on cluster version and such
        kube: import "vendor/github.com/jsonnet-libs/k8s-libsonnet/1.23/main.libsonnet",
        flux: import "vendor/github.com/jsonnet-libs/fluxcd-libsonnet/0.30.2/main.libsonnet",
        certs: import "vendor/github.com/jsonnet-libs/cert-manager-libsonnet/1.7/main.libsonnet",
        prom: import "vendor/github.com/jsonnet-libs/kube-prometheus-libsonnet/0.10/main.libsonnet",
        tanka: import "vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet",
        externalSecrets: import "vendor/github.com/jsonnet-libs/external-secrets-libsonnet/0.5/main.libsonnet"
    },

    kube: $._local.kube + {
        networking+: {
            v1+: {
                networkPolicyIngressRule+: {
                    withFromCidrs(cidrs):: super.withFrom([
                        $.kk.networkPolicyPeer.ipBlock.withCidr(cidr)
                        for cidr in cidrs
                    ])
                }
            }
        }
    },

    flux: $._local.flux,
    certs: $._local.certs,
    prom: $._local.prom,
    kapitan: $._local.kapitan,
    tanka: $._local.tanka,
    externalSecrets: $._local.externalSecrets,

    kk: {
        # common aliases for k8s resources
        configMap: $.kube.core.v1.configMap,
        container: $.kube.core.v1.container,
        containerPort: $.kube.core.v1.containerPort,
        deployment: $.kube.apps.v1.deployment,
        ingress: $.kube.networking.v1.ingress,
        localObjectReference: $.kube.core.v1.localObjectReference,
        namespace: $.kube.core.v1.namespace,
        networkPolicy: $.kube.networking.v1.networkPolicy,
        networkPolicyIngressRule: $.kube.networking.v1.networkPolicyIngressRule,
        networkPolicyPeer: $.kube.networking.v1.networkPolicyPeer,
        networkPolicyPort: $.kube.networking.v1.networkPolicyPort,
        objectMeta: $.kube.meta.v1.objectMeta,
        persistentVolumeClaim: $.kube.core.v1.persistentVolumeClaim,
        resourceRequirements: $.kube.core.v1.resourceRequirements,
        secret: $.kube.core.v1.secret,
        service: $.kube.core.v1.service,
        serviceAccount: $.kube.core.v1.serviceAccount,
        servicePort: $.kube.core.v1.servicePort,
        storageClass: $.kube.storage.v1.storageClass,
        volume: $.kube.core.v1.volume,
        volumeMount: $.kube.core.v1.volumeMount,

        # cert-manager stuff
        certificate: $.certs.nogroup.v1.certificate,
        certificateRequest: $.certs.nogroup.v1.certificateRequest,
        clusterIssuer: $.certs.nogroup.v1.clusterIssuer,
        issuer: $.certs.nogroup.v1.issuer,

        # prometheus stuff
        podMonitor: $.prom.monitoring.v1.podMonitor,
        serviceMonitor: $.prom.monitoring.v1.serviceMonitor,

        # returns whether the specified object is a Kubernetes resource
        isResource(data)::
            std.objectHas(data, "kind")
            && std.objectHas(data, "metadata")
            && std.objectHas(data.metadata, "name"),

        # applies a function recursively to Kubernetes resources
        applyRecursive(data, fn)::
            local recurse = function(data, fn, i) if std.isObject(data) then
                if $.kk.isResource(data) then fn(data) else if i <= 10 then
                    std.mapWithKey(function(_, v) recurse(v, fn, i+1), data)
                else data
            else data;
        recurse(data, fn, 0),

        # helper function to invoke a Helm build enlightened with our context defaults
        helmTemplate(helm, name, chart, version, namespace,
            crds=false,
            values={},
            extraArgs={}
        )::
            helm.template(name, std.format("charts/%s/%s", [chart, version]), {
                namespace: namespace,
                includeCrds: crds,
                kubeVersion: inputs.cluster.version,
                skipTests: true,
                values: values
            } + extraArgs),

        # removes CRDs from an attribute set of resources
        removeCrds(data):: $.kk.filterObject(data,
            function(v) v.kind != "CustomResourceDefinition"),

        # filter an attribute set
        filterObject(data, f):: {
            [x]: data[x] for x in std.objectFields(data) if f(data[x])
        },

        withNamespace(namespace):: {
            metadata+: { namespace: namespace }
        },

        withAnnotations(annotations):: {
            metadata+: $.kk.objectMeta.withAnnotations(annotations)
        },

        withAnnotationsMixin(annotations):: {
            metadata+: $.kk.objectMeta.withAnnotationsMixin(annotations)
        },

        withFluxLayer(layer):: $.kk.withAnnotationsMixin({
            "fractal.k8s.arctarus.net/flux-layer": layer
        }),

        withFluxPath(path):: $.kk.withAnnotationsMixin({
            "fractal.k8s.arctarus.net/flux-path": path
        })
    }
}
+ utils
