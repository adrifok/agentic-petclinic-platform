ECR image build and push

Last updated: 2026-09-07

Purpose: how the initial (and any manual) Docker image build/push to ECR
works, and why it does not use the application repo's -P buildDocker Maven
profile. Implements PETPLAT-85.

Why not -P buildDocker

The app repo's buildDocker profile (pom.xml) shells out via exec-maven-plugin
to plain "docker build --load", bound to Maven's install phase. Its defaults:

  container.platform    = linux/amd64  (must override to linux/arm64)
  docker.image.prefix   = springcommunity  (hardcoded, not this platform's ECR path)
  container.build.extraarg = --load  (local daemon only, no push)
  image tag             = implicit "latest" (no commit SHA)

None of that matches this platform's convention: images live at
{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/{service},
tagged with a commit SHA or explicit version, never "latest" (see
docs/technical-spec.md#ecr-container-registry and #docker-build). The app
repo is read-only (see CLAUDE.md), so the profile itself can't be changed to
fix the prefix, add SHA tagging, or add --push. Maven's job is reduced to
producing the JARs; docker buildx owns the image, tag, platform, and push.

Procedure: build and push all 8 images

When: initial bootstrap before any K8s manifests can be deployed (images
must exist in ECR first), or any manual rebuild/push outside CI.
Who: whoever holds AWS credentials with ecr:GetAuthorizationToken,
ecr:BatchCheckLayerAvailability, ecr:PutImage, and the layer upload actions
(ecr:InitiateLayerUpload, ecr:UploadLayerPart, ecr:CompleteLayerUpload) on
the target repositories — the same least-privilege set specified for the
future CI role in docs/technical-spec.md#cicd-pipeline, not ecr:*.
Time: ~10-15 minutes (Maven build once, then 8 sequential ARM64 buildx
builds under QEMU emulation on an x86_64 workstation).

Steps:
1. Ensure the ECR repositories already exist (terraform apply in
   terraform/environments/dev — PETPLAT-20).
2. Run the script from the platform repo root:

     ./scripts/build-push-images.sh dev

   Optional second argument pins the tag (defaults to the app repo's short
   commit SHA); optional third argument points at the app repo checkout if
   it isn't a sibling of this repo:

     ./scripts/build-push-images.sh dev v1.0.0 /path/to/spring-petclinic-microservices

   The script: runs "mvnw clean package" (JARs only, no buildDocker), logs
   in to ECR via scripts/ecr-login.sh, then per service either
   builds+scans+pushes (when trivy is installed — fails on CRITICAL CVEs,
   matching CLAUDE.md's CI/CD scanning convention) or builds+pushes in one
   "docker buildx build --platform linux/arm64 ... --push" step and relies
   on ECR's scan-on-push (asynchronous, detective only) when trivy isn't
   available locally.

Verify:
- Console: https://eu-central-1.console.aws.amazon.com/ecr/repositories
- CLI, per repository:

    aws ecr describe-images --repository-name petclinic-dev/customers-service --region eu-central-1

- All 8 repositories show the tag the script printed at the end.

Rollback:
- Nothing is deployed by this script — it only pushes images. To remove a
  bad push, delete the specific image tag:

    aws ecr batch-delete-image --repository-name petclinic-dev/{service} \
      --image-ids imageTag={tag} --region eu-central-1

Runtime ports — do not trust pom.xml

Several modules' docker.image.exposed.port property is wrong (a copy-paste
leftover): api-gateway, vets-service, and genai-service all show 8081;
visits-service uses a mistyped property name and silently falls back to the
parent's 9090. The script hardcodes the real ports from
docs/technical-spec.md#application-services instead. If a service's actual
port ever changes, update the PORTS array in scripts/build-push-images.sh
to match the spec, not the app repo's pom.xml.

CI equivalent

PETPLAT-49 (not yet built) automates this same buildx-not-buildDocker
approach in .github/workflows/build-push.yml, matrixed per changed service
via dorny/paths-filter, authenticating via OIDC instead of a local
aws sts identity. See docs/technical-spec.md#cicd-pipeline.
