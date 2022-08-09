# Abridged Tour of GitHub Workflows

```
.github/
├── actions
│   ├── helm
│   │   └── action.yml
│   └── release-notes
│       ├── Dockerfile
│       ├── action.yml
│       └── entrypoint.sh
├── policy
│   ├── kubernetes.rego
│   └── rules.rego
└── workflows
    ├── build-flux-oci-prerelease.yaml
    ├── docker-build.yml
    ├── flux-push-artifact-production.yaml
    └── flux-push-artifact-staging.yaml
```

**Note**:
* `.github/workflows/**`:
  * `build-flux-oci-prerelease.yaml` - Used to prepare a `flux` CLI from WIP `oci` branch
  * `docker-build.yml` - Build and push App Image for branches and tags<br/>
    (`docker build` and `docker push`)
  * `flux-push-artifact-staging.yaml` - Build and push OCI for a staging environment<br/>
    (`flux push` and `flux tag staging` from the main Git branch)
  * `flux-push-artifact-production.yaml` - Build and push OCI for a prod environment<br/>
    (`flux push` and `flux tag production` from Git tags)

**Disregard these**:
* `.github/actions/**` - Not used in this example
* `.github/policy/*` - Not used
