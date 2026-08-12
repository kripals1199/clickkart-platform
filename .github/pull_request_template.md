## What changed

<!-- One or two sentences. -->

## Checklist

- [ ] No secrets or real credentials added (this repository is **public**)
- [ ] If this changes an environment's config, the same change was applied to every other
      environment branch that needs it — branches are independent, not stacked
- [ ] If this adds a required env var with no default, the corresponding k8s manifest
      ConfigMap/Secret was updated too, or the pod will crash-loop on startup

## Risk

<!-- What could this break? Does it need a coordinated deploy? -->
