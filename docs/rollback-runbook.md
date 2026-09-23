# Rollback Runbook

**Last Updated:** 2026-09-23

**Purpose:** Get a service back to a known-good image after a bad deployment. Implements PETPLAT-54; related to PETPLAT-50 / PETPLAT-87 (`.github/workflows/update-image-tags.yml`). See `docs/technical-spec.md#cicd-pipeline` and `#gitops-with-argocd`.

## Table of Contents

- [How a Deployment Happens](#how-a-deployment-happens)
- [Procedure: Pre-Rollback Checks](#procedure-pre-rollback-checks)
- [Procedure: GitOps Rollback (default)](#procedure-gitops-rollback-default)
- [Procedure: ArgoCD Rollback (fast, temporary)](#procedure-argocd-rollback-fast-temporary)
- [Procedure: Emergency Cluster-Side Rollback](#procedure-emergency-cluster-side-rollback)
- [Procedure: Rollback Drill](#procedure-rollback-drill)

## How a Deployment Happens

1. `build-push.yml` in the application repo fork builds the changed services, pushes `petclinic-{env}/{service}:{sha}` to ECR, then fires `repository_dispatch` event `app-image-built` at this platform repo (PETPLAT-49).
2. `update-image-tags.yml` sets `image.tag` in `helm-values/{service}.yaml` to that SHA and pushes a commit to `main`: `ci: update image tags to {sha} ({service-list})`.
3. ArgoCD renders `helm/petclinic-service/` with `helm-values/{service}.yaml` + `helm-values/{env}.yaml`. Dev auto-syncs (prune + self-heal); prod waits for a manual sync.

Git is the source of truth. A rollback that is not also in Git gets undone: in dev by ArgoCD self-heal, in prod by the next manual sync.

- `helm-values/{service}.yaml` is shared by dev and prod — an `image.tag` change there applies to both. Prod only moves when someone syncs it.
- ArgoCD is not installed yet (E-17). Until it is, deployments are manual `helm upgrade --install` runs (`docs/helm-guide.md`); only the Git part of the GitOps procedure and the emergency procedure apply.

The examples below use `customers-service` in dev. Set these once per shell:

```bash
SERVICE=customers-service
ENV=dev
```

---

### Procedure: Pre-Rollback Checks

**When:** Before any rollback.
**Who:** On-call engineer with kubectl access to the cluster and ECR read access.
**Time:** 5 minutes.

**Steps:**
1. Find the last good SHA from the tag history:
   ```bash
   git log --oneline -- "helm-values/${SERVICE}.yaml"
   ```
2. Check what is currently running:
   ```bash
   kubectl get deploy "${SERVICE}" -n "petclinic-${ENV}" -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
   ```
3. Confirm the good image still exists in ECR. The lifecycle policy (`terraform/modules/ecr/`, `max_image_count = 10`) keeps only the last 10 images per repo, so an old target may be expired:
   ```bash
   aws ecr describe-images --region eu-central-1 --repository-name "petclinic-${ENV}/${SERVICE}" --image-ids imageTag=<good-sha>
   ```
4. If the image is gone, check out `<good-sha>` in the app repo and rebuild it before rolling back:
   ```bash
   ./scripts/build-push-images.sh "${ENV}" <good-sha> <path-to-app-repo>
   ```
5. customers/visits/vets share one MySQL database. Check whether the bad release changed the schema — an older image may not run against a schema a newer one already altered.

**Verify:**
- You have a `<good-sha>` that exists in ECR.

**Rollback:**
- Read-only checks, nothing to undo.

---

### Procedure: GitOps Rollback (default)

**When:** A deployment from `update-image-tags.yml` is bad and Git access is available.
**Who:** Engineer with push access to the platform repo `main`.
**Time:** 5–10 minutes (ArgoCD polls every 3 minutes by default).

**Steps:**
1. Revert the tag-update commit. This rolls back exactly the services that commit touched:
   ```bash
   git pull origin main && \
   git log --oneline --grep '^ci: update image tags' -5 && \
   git revert --no-edit <bad-commit-sha> && \
   git push origin main
   ```
2. Or roll back a single service out of a multi-service commit. `yq` drops blank lines, so the `sed` wrapper keeps the diff to one line (same as the workflow):
   ```bash
   git pull origin main && \
   f="helm-values/${SERVICE}.yaml" && \
   sed -i 's/^$/#__BLANK__/' "$f" && \
   GOOD_SHA=<good-sha> yq -i '.image.tag = strenv(GOOD_SHA)' "$f" && \
   sed -i 's/^#__BLANK__$//' "$f" && \
   git diff && \
   git commit -am "fix(helm): roll back ${SERVICE} to <good-sha>" && \
   git push origin main
   ```
3. Dev syncs automatically; to force it now:
   ```bash
   argocd app sync "${SERVICE}-dev"
   ```
4. Prod (manual sync, as always):
   ```bash
   argocd app sync "${SERVICE}-prod"
   ```
5. Before ArgoCD exists, deploy the reverted tag manually:
   ```bash
   helm upgrade --install "${SERVICE}" helm/petclinic-service/ -n "petclinic-${ENV}" -f "helm-values/${SERVICE}.yaml" -f "helm-values/${ENV}.yaml"
   ```

**Verify:** see [Verify Recovery](#verify-recovery).

**Rollback:**
- Revert the revert (`git revert --no-edit <revert-commit-sha> && git push origin main`).

---

### Procedure: ArgoCD Rollback (fast, temporary)

**When:** The service must be restored before a Git revert can land.
**Who:** Engineer with ArgoCD admin access.
**Time:** 2–5 minutes.

ArgoCD refuses to roll back while auto-sync is on, so dev must switch it off first (prod is manual sync already).

**Steps:**
1. Disable auto-sync (dev only), inspect history, roll back:
   ```bash
   argocd app set "${SERVICE}-dev" --sync-policy none && \
   argocd app history "${SERVICE}-dev" && \
   argocd app rollback "${SERVICE}-dev" <history-id>
   ```
   UI equivalent: Application → History and Rollback → select revision → Rollback.
2. The app now shows `OutOfSync` because Git still has the bad tag. Run the [GitOps Rollback](#procedure-gitops-rollback-default).
3. Re-enable auto-sync once Git holds the good tag:
   ```bash
   argocd app set "${SERVICE}-dev" --sync-policy automated --auto-prune --self-heal
   ```

**Verify:** see [Verify Recovery](#verify-recovery); `argocd app get "${SERVICE}-dev"` shows `Synced` / `Healthy` after step 3.

**Rollback:**
- `argocd app rollback "${SERVICE}-dev" <newer-history-id>`.

---

### Procedure: Emergency Cluster-Side Rollback

**When:** ArgoCD is unavailable, or before ArgoCD is installed.
**Who:** On-call engineer with kubectl/helm access to the namespace.
**Time:** 2–5 minutes.

With ArgoCD running in dev, self-heal undoes this immediately unless auto-sync is disabled first (see ArgoCD Rollback step 1).

**Steps:**
1. Helm-managed releases (current state, no ArgoCD) — keeps Helm history accurate:
   ```bash
   helm history "${SERVICE}" -n "petclinic-${ENV}" && \
   helm rollback "${SERVICE}" <revision> -n "petclinic-${ENV}" --wait
   ```
2. Or directly on the Deployment:
   ```bash
   kubectl rollout undo "deployment/${SERVICE}" -n "petclinic-${ENV}" && \
   kubectl rollout status "deployment/${SERVICE}" -n "petclinic-${ENV}" --timeout=300s
   ```
3. Fix Git with the [GitOps Rollback](#procedure-gitops-rollback-default) so the next deploy does not bring the bad tag back.

**Verify:** see [Verify Recovery](#verify-recovery).

**Rollback:**
- `helm rollback "${SERVICE}" <newer-revision> -n "petclinic-${ENV}" --wait`.

---

### Verify Recovery

```bash
kubectl rollout status "deployment/${SERVICE}" -n "petclinic-${ENV}" --timeout=300s && \
kubectl get pods -n "petclinic-${ENV}" -l "app.kubernetes.io/name=${SERVICE}" -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.containers[0].image}{"\n"}{end}' && \
HOST=$(terraform -chdir="terraform/environments/${ENV}" output -raw dns_record_name) && \
curl -s -o /dev/null -w "%{http_code}\n" "https://${HOST}/api/customer/owners"
```

Expect: rollout complete, pod image ends in `<good-sha>`, HTTP `200`. With ArgoCD: `argocd app get "${SERVICE}-${ENV}"` shows `Synced` / `Healthy`.

---

### Procedure: Rollback Drill

**When:** PETPLAT-54 acceptance test, and after any change to the CI/CD flow. Dev only.
**Who:** Engineer with push access to the platform repo and a `gh` token with `repo` scope.
**Time:** 15–20 minutes.

**Steps:**
1. Deploy a bad image — a tag that does not exist in ECR is enough (`ImagePullBackOff`). `gh api` nested-field syntax builds `client_payload` as JSON:
   ```bash
   PLATFORM_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner) && \
   gh api "repos/${PLATFORM_REPO}/dispatches" \
     -f event_type=app-image-built \
     -f 'client_payload[sha]=0000000' \
     -f 'client_payload[services][]=vets-service'
   ```
2. Wait for the `update-image-tags` run and the ArgoCD sync, then confirm the failure:
   ```bash
   gh run list --workflow update-image-tags.yml -L 1 && \
   kubectl get pods -n petclinic-dev -l app.kubernetes.io/name=vets-service
   ```
3. Run the [GitOps Rollback](#procedure-gitops-rollback-default) with `SERVICE=vets-service`, reverting the `ci: update image tags to 0000000 (vets-service)` commit.
4. Confirm recovery with [Verify Recovery](#verify-recovery) and record the time from revert push to `Ready` pod.

**Verify:**
- `vets-service` is `Running`/`Ready` on its previous tag; `helm-values/vets-service.yaml` no longer contains `0000000`.

**Rollback:**
- Nothing to undo — the drill ends in the original state.
