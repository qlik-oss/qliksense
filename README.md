# Qlik Sense Enterprise on Kubernetes

## What is this Repository?

This repository contains a filesystem structure that allows for the rendering of QSEoK manifests using the [qlik-oss version](https://github.com/qlik-oss/kustomize/releases) 
of [`kustomize`](https://kustomize.io/). `kustomize` is used to perform "last mile" modifications to component helm charts rendered using `helm template` to provide a 
configuration interface using change fragments (patches) of kubernetes resources using label selectors.

Generally, performing configuration for Qlik Sense is done through the CLI and associated operators, this repository is what is used by those components as the initial state of the cluster prior to configuration. Manual creation of patches in this repository directly is meant for advanced configuarations not handled by the operator.


## Quickstart

By cloning this repository or downloading and unpacking an archive from the releases page you can render a QSEoK manifest for a given profile (current only Docker Desktop is supported).
To render a manifest for a Docker Desktop kubernetes QSEoK cluster instance:

1. Download [`kustomize`](https://kustomize.io/) from [qlik-oss](https://github.com/qlik-oss/kustomize/releases) and put it in your `PATH`. (This is a convienient pre-built version of `kustomize` with all the necessary plugins compiled into it)
2. Download [`gomplate`](https://github.com/hairyhenderson/gomplate/releases/) for your platform and put it in your `PATH`
3. Download [`helm`](https://github.com/helm/helm/releases/tag/v2.16.1) v2.x latest and put it in your `PATH`
4. Set an environment variable for a resource decryption key:
   - Bash:
     - `export EJSON_KEY=a8dc748390aac1c60c434d52f32ffb3c37870153d34ace6f526bf1f9d987439d`
   - PowerShell:
     - `$Env:EJSON_KEY="a8dc748390aac1c60c434d52f32ffb3c37870153d34ace6f526bf1f9d987439d"`
5. Navigate into the `qliksense-k8s` directory and execute `kustomize build manifests/docker-desktop`

While you can apply this manifest to your local desktop cluster, the `engine` pods will likely fail as the EULA needs to be explictely accepted.
To do this, you need to patch the engine ConfigMap resource directly that contains this setting using a `kustomize` custom resource (`SelectivePatch`) that contains the patch:

6. Create a file called `acceptEULA.yaml` with that content, place it into the `configuration/patches` directory. This file contains a 
   - Bash:
     - ```yaml
       bash# pushd .
       bash# cd configuration/patches 
       bash# cat <<EOT >> acceptEULA.yaml
       apiVersion: qlik.com/v1
       kind: SelectivePatch
       metadata:
          name: acceptEULA
       enabled: true
       patches:
         - patch: |-
             apiVersion: v1
             kind: ConfigMap
             metadata:
               name: engine-configs
             data:
               acceptEULA: 'yes'
       EOT
       bash# kustomize edit add resource acceptEULA.yaml
       bash# popd
       ```
   - PowerShell:
     - ```yaml
       PS> Push-Location
       PS> Set-Location configuration\patches
       PS> Add-Content -Value @"
       apiVersion: qlik.com/v1
       kind: SelectivePatch
       metadata:
          name: acceptEULA
       enabled: true
       patches:
         - patch: |-
             apiVersion: v1
             kind: ConfigMap
             metadata:
               name: engine-configs
             data:
               acceptEULA: 'yes'
       "@ -Path .\acceptEULA.yaml
       PS> kustomize edit add resource acceptEULA.yaml
       PS> Pop-Location
       ```
    
7. Navigate into the `qliksense-k8s` directory and execute `kustomize build manifests/docker-desktop`, you can also apply the manifest to a cluster using `kustomize build manifests/docker-desktop | kubectl apply -f - `

### Learning through Examples: Typical Use cases

### Specifying replicas

(Examples will use base, for Windows PowerShell, use the same scripting patterns as the quickstart above)

It is possible to specify replicas for resources based on label selectors. For example to specify 3 replicas for all deployments. 
Create a file called `relicas.yaml` with that content, place it into the `configuration/patches` directory. This file contains a 
```yaml
bash# pushd .
bash# cd configuration/patches 
bash# cat <<EOT >> replicas.yaml
apiVersion: qlik.com/v1
kind: SelectivePatch
metadata:
  name: replicas
enabled: true
patches:
  - target:
      kind: Deployment
    patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: notneeded
      spec:
        replicas: 3
 EOT
 bash# kustomize edit add resource relicas.yaml
 bash# popd
 ```
Notice that what is specified in `target` indicates a "target" and takes precendence over that which is specified `metadata.name` of the patch.
In this case, it means "Apply the following patch to all targets where `kind` is `Deployment`".

We  may want to be more specific for the replicas of the `audit` component, in which case we would replace the corresponding section above with:
```yaml
patches:
  - target:
      kind: Deployment
      labelSelector: app=audit
    patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: notneeded
      spec:
        replicas: 3
```
An alternate version, is to allow the patch to indiciate the target via it's ond group-version-kind (GVK) data and `name` (used when there is no `target`).
```yaml
patches:
  - patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: audit
      spec:
        replicas: 3
```
It is also possible to use a [JSON 6902 patch](http://jsonpatch.com/). This always requires a target as the patch never containss GVK or name data.
```yaml
patches:
  - target:
      kind: Deployment
      labelSelector: app=audit
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
```
or, more simply
```yaml
patches:
  - target:
      kind: Deployment
      name: audit
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
```
Replicas for all Deployments except audit and collections
```yaml
patches:
  - target:
      kind: Deployment
      labelSelector: "app notin (audit,collections)"
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
```
Replicas for all Deployments except audit and collections
```yaml
patches:
  - target:
      kind: Deployment
      labelSelector: "app notin (audit,collections)"
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
```

### Setting resource limits

By default, qseok, does not come with any resource limits defined. To create a limit for collections and audit:
```yaml
patches:
 - target:
      kind: Deployment
      labelSelector: "app in (audit,collections)"
  - patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: component
      spec:
        template:
          spec:
            containers:
              - name: main
                resources: 
                  limits:
                    memory: 512Mi
                  requests:
                    cpu: 100m
                    memory: 128Mi
```
In the same way as replicas is used, coll

### Configuring an IDP
For General documentation on configing IDPs on QSEoK go to Qlik Sense Help.

When configuring any IDP, it requires the following JSON file per IDP:
```json
{
  "claimsMapping": {
    "name": "name",
    "sub": [
        "sub",
        "client_id"
    ]
  },
  "clientId": "foo",
  "clientSecret": "bar",
  "hostname": "elastic.example",
  "issuerConfig": {
    "authorization_endpoint": "http://elastic.example:32123/auth",
    "end_session_endpoint": "http://elastic.example:32123/session/end",
    "introspection_endpoint": "http://elastic.example:32123/token/introspection",
    "issuer": "http://simple-oidc-provider",
    "jwks_uri": "http://elastic.example:32123/certs",
    "token_endpoint": "http://elastic.example:32123/token",
    "userinfo_endpoint": "http://elastic.example:32123/me"
  },
  "postLogoutRedirectUri": "http://elastic.example",
  "realm": "simple"
}
```
The simplest way to patch this configuration into the identify services is to supply it to the indentity providers service
secret (where it is stored) as string data:

```yaml
patches:
  - patch: |-
      apiVersion: v1
      kind:Secret
      metadata:
        name: identity-providers-secrets
      stringData:
        idpConfigs: |-
          [ {
              "claimsMapping": {
                "name": "name",
                "sub": [
                    "sub",
                    "client_id"
                ]
              },
              "clientId": "foo",
              "clientSecret": "bar",
              "hostname": "elastic.example",
              "issuerConfig": {
                "authorization_endpoint": "http://elastic.example:32123/auth",
                "end_session_endpoint": "http://elastic.example:32123/session/end",
                "introspection_endpoint": "http://elastic.example:32123/token/introspection",
                "issuer": "http://simple-oidc-provider",
                "jwks_uri": "http://elastic.example:32123/certs",
                "token_endpoint": "http://elastic.example:32123/token",
                "userinfo_endpoint": "http://elastic.example:32123/me"
              },
              "postLogoutRedirectUri": "http://elastic.example",
              "realm": "simple"
            }
          ]
```
As what is being patched is a secret it is also possible to supply the value for idpConfigs as base64 in the `data:`
section.



### Adding a custom root CA certificate (for IDP)

### Setting a global storage class

### Setting a global docker image registry

### Generate a secret from vault

The [`kustomize`](https://kustomize.io/) version from [qlik-oss](https://github.com/qlik-oss/kustomize/releases) has a builtin `gomplate` plugin that allows secrets to be pulled from vault.
You should hav downloaded [`gomplate`](https://github.com/hairyhenderson/gomplate/releases/) an put it you path as part of the "quickstart" above.

As we are using Vault, we will need a vault address specifying the base in which to find the secret and and address. These environmental variables are set prior to the generation of the manifest through `kustomize build .`:
   - Bash:
     - `export VAULT_ADDR=https://127.0.0.1:8200`
     - `export VAULT_TOKEN=a8dc748390aac1c60c434d52f32ffb3c37870153d34ace6f526bf1f9d987439d`
   - PowerShell:
     - `$Env:VAULT_ADDR=https://127.0.0.1:8200`
     - `$Env:VAULT_TOKEN="a8dc748390aac1c60c434d52f32ffb3c37870153d34ace6f526bf1f9d987439d"`

To pull a secret from vault, a special type of patch needs to be used. We will use the "Configuring an IDP" example, in which case the folling IDP configuration array is stored in vault:

```json
[ {
    "claimsMapping": {
      "name": "name",
      "sub": [
          "sub",
          "client_id"
      ]
    },
    "clientId": "foo",
    "clientSecret": "bar",
    "hostname": "elastic.example",
    "issuerConfig": {
      "authorization_endpoint": "http://elastic.example:32123/auth",
      "end_session_endpoint": "http://elastic.example:32123/session/end",
      "introspection_endpoint": "http://elastic.example:32123/token/introspection",
      "issuer": "http://simple-oidc-provider",
      "jwks_uri": "http://elastic.example:32123/certs",
      "token_endpoint": "http://elastic.example:32123/token",
      "userinfo_endpoint": "http://elastic.example:32123/me"
    },
    "postLogoutRedirectUri": "http://elastic.example",
    "realm": "simple"
  }
]
```

The patch consists of files (that are added to the patches kustomization.yaml). As this is not a patch on the kubernetes resource API, but rather a patch on a kuztomize custom kind called `SuperSecret` used to generate the kubernetes `Secret` kind, it is specified in a different location: `configuration/secrets`. 
Two resources will be created, a gomplate transformer, that instructs `kustomize` to execute gomplate on the resources according to this specification:
```yaml
apiVersion: qlik.com/v1
kind: Gomplate
metadata:
  name: identity-service-vault-secrets
  labels:
    key: gomplate
dataSource:
  vault:
    secretPath: path/to/key/values/with/secret
  
```
And the resource patch itself on the `SuperSecret` type for `identity-providers`:
```yaml
apiVersion: qlik.com/v1
kind: SelectivePatch
metadata:
  name: identity-service-mysecrets
enabled: true
patches:
- target:
    kind: SuperSecret
  patch: |-
    apiVersion: qlik.com/v1
    kind: SuperSecret
    metadata:
      name: identity-providers-secrets
    stringData:
      idpConfigs: |-
        (( (ds "vault").idpConfigs | indent 8 ))
```

These needed now need to be added to kustomize in the appropriate directory:
   - Bash:
     - ```yaml
       bash# pushd .
       bash# cd configuration/secrets 
       bash# cat <<EOT >> identity-providers-mysecrets.yaml
       apiVersion: qlik.com/v1
       kind: SelectivePatch
       metadata:
         name: identity-providers-secrets
       enabled: true
       patches:
       - target:
           kind: SuperSecret
         patch: |-
           apiVersion: qlik.com/v1
           kind: SuperSecret
           metadata:
             name: identity-providers-secrets
           stringData:
             idpConfigs: |-
               (( (ds "vault").idpConfigs | indent 8 ))
       EOT
       bash# kustomize edit add resource identity-providers-mysecrets.yaml
       bash# cat <<EOT >> identity-providers-vault-secrets.yaml
       apiVersion: qlik.com/v1
       kind: Gomplate
       metadata:
         name: identity-providers-vault-secrets
         labels:
           key: gomplate
       dataSource:
         vault:
           secretPath: path/to/key/values/with/secret
       EOT
       bash# cat <<EOT >> kustomization.yaml
       transformers:
       - identity-providers-vault-secrets.yaml
       EOT
       bash# popd
       ```
   - PowerShell:
     - ```yaml
       PS> Push-Location
       PS> Set-Location configuration\secrets
       PS> Add-Content -Value @" 
       apiVersion: qlik.com/v1
       kind: SelectivePatch
       metadata:
         name:  identity-providers-secrets
       enabled: true
       patches:
       - target:
           kind: SuperSecret
         patch: |-
           apiVersion: qlik.com/v1
           kind: SuperSecret
           metadata:
             name: identity-providers-secrets
           stringData:
             idpConfigs: |-
               (( (ds "vault").idpConfigs | indent 8 ))
       "@ -Path .\identity-providers-mysecrets.yaml
       PS> kustomize edit add resource identity-providers-mysecrets.yaml
       PS> Add-Content -Value @"
       apiVersion: qlik.com/v1
       kind: Gomplate
       metadata:
         name:  identity-providers-vault-secrets
         labels:
           key: gomplate
       dataSource:
         vault:
           secretPath: path/to/key/values/with/secret
       "@ -Path .\ identity-providers-vault-secrets.yaml
       PS> Add-Content -Value @"
       transformers:
       -  identity-providers-vault-secrets.yaml
       "@ -Path .\kustomization.yaml
       PS> Pop-Location
       ```

Generating the manifest should now also pull the IDP configuration from vault.

This method can be used for any secret or configs. In the case of configs, the resources types is
`SuperConfigMap` for the `kustomize` kind and use the `-configs` postfix for resource names.

## Design Details

### Rationale

As a platform, QSEoK needs to:
a) provide a consistent kubernetes resource layout that allows for higher order operations across all components;
  - Ex. Set a global private registry, use a pvc storage class
b) be able to implement higher order operations without needing to invoke component specific templating logic (consistency);
c) allow for changes to the kubernetes resources so they can be modified directly and not break higher order operations without having to invoke templating logic to export the capability through templating;
  - Ex. Add a side car, provide custom annotation
d) provide an intial cluster state that can be forked in order to provide an intial state for GitOps cluster management;
e) use Git tag versioning as the source of truth for kubernetes infrastucture-as-code releases of QSEoK.
f) decouple configuration logic from service implementation logic

### How manifests are rendered

#### Components

In order to facilate a) ("Rationale"), components are expected to render are consistent kubernets API. Bespoke components are required to render the required layouts directly from helm using defaults. Off-the-shell
components will be patched immediately from the helm rendering to conform the the required layout.

Thje lao

### Installation of Qliksense

- Install Porter from here: https://porter.sh/install/
- Install the followiung Mixins:
  - `porter mixin install kustomize -v 0.2-beta-3-0e19ca4 --url https://github.com/donmstewart/porter-kustomize/releases/download`
  - `porter mixin install qliksense -v v0.14.0 --url https://github.com/qlik-oss/porter-qliksense/releases/download`
- Run Porter build: `porter build -v`
- Ensure connectivity to the target cluster create a kubeconfig credential `porter cred generate`
  - Select `specific value` at the prompt and specify the value. 
  - Select `file path` and specify full path to kube config file ex. `/home/user/.kube/config` or  `C:\Users\.kube\config `
  
- Install the bundle : `porter install --param acceptEULA=yes -c QLIKSENSE`
- Notice `acceptEULA` key has been updated inside `qliksense-configs-<hash>` configMap.

## Generate Credentials from published bundle**

- `porter credential generate demo3 --tag qlik/qliksense-cnab-bundle:v0.1.0`

## Supported Parameters during install

| Name        | Descriptions           | Default  |
| ------------- |:-------------:| -----:|
| profile      | select a profile i.e docker-desktop, aws-eks, gke | docker-desktop |
| acceptEULA      | yes | has to be yes |
| namespace      | any kubernetes namespace      |   default |
| rotateKeys | regenerate application PKI keys on upgrade (yes/no)      |    no |
| scName | storage class name      |    none |

## How To Add Identity Provider Config

since idp configs are usually multiline configs it is not conventional to pass to porter during install as a `param`. Rather put the configs in a file and refer to that file during `porter install` command. For example to add `keycloak` IDP create file named `idpconfigs.txt` and put

```console
idpConfigs=[{"discoveryUrl":"http://keycloak-insecure:8089/keycloak/realms/master22/.well-known/openid-configuration","clientId":"edge-auth","clientSecret":"e15b5075-9399-4b20-a95e-023022aa4aed","realm":"master","hostname":"elastic.example","claimsMapping":{"sub":["sub","client_id"],"name":["name","given_name","family_name","preferred_username"]}}]

```

Then pass that file during install command like this

```console
porter install --param acceptEULA=yes -c QLIKSENSE --param-file idpconfigs.txt
```

## Service configuration

For information on configuring services to become kubernetes-compatible [refer here](How-to.md)
