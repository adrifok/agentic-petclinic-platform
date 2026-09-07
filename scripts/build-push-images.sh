#!/usr/bin/env bash
#
# build-push-images.sh — build the 8 Petclinic service JARs with Maven, then
# build and push linux/arm64 (Graviton) images to ECR with docker buildx.
#
# Deliberately does NOT use the application repo's `-P buildDocker` Maven
# profile: that profile shells out to plain `docker build --load` with a
# hardcoded `springcommunity/` image prefix, no commit-SHA tagging, and no
# --push — none of which match this platform's ECR naming/tagging
# convention, and the app repo is read-only so the profile can't be fixed
# there. Maven's job here is the JAR only; docker buildx owns the image,
# the tag, the platform, and the push to ECR.
#
# Usage:
#   ./scripts/build-push-images.sh <dev|prod> [tag] [app_repo_dir]
#
#   tag           Image tag (default: the app repo's short 7-char commit SHA)
#   app_repo_dir  Path to a spring-petclinic-microservices checkout
#                 (default: $APP_REPO_DIR env var, else a sibling-checkout
#                 guess next to this repo — pass explicitly if that's wrong)
#
# See docs/technical-spec.md#docker-build, #ecr-container-registry, and
# docs/runbooks/ecr-image-build-push.md for the full write-up. PETPLAT-85.

set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-eu-central-1}"

usage() {
  echo "Usage: $0 <dev|prod> [tag] [app_repo_dir]"
  exit 1
}

[[ $# -ge 1 ]] || usage

ENV="$1"
if [[ "${ENV}" != "dev" && "${ENV}" != "prod" ]]; then
  echo "Error: environment must be 'dev' or 'prod'" >&2
  usage
fi

ARG_TAG="${2:-}"
ARG_APP_REPO_DIR="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Sibling-checkout guess: .../<parent>/petclinic-platform/<this repo>/scripts
# -> up 3 -> .../<parent>/spring-petclinic/spring-petclinic-microservices.
# Adjust via $APP_REPO_DIR or the third argument if your layout differs.
DEFAULT_APP_REPO_DIR="$(cd "${SCRIPT_DIR}/../../../spring-petclinic/spring-petclinic-microservices" 2>/dev/null && pwd || true)"
APP_REPO_DIR="${ARG_APP_REPO_DIR:-${APP_REPO_DIR:-${DEFAULT_APP_REPO_DIR}}}"

if [[ -z "${APP_REPO_DIR}" || ! -f "${APP_REPO_DIR}/pom.xml" || ! -f "${APP_REPO_DIR}/docker/Dockerfile" ]]; then
  echo "Error: '${APP_REPO_DIR}' doesn't look like a spring-petclinic-microservices checkout (no pom.xml / docker/Dockerfile)." >&2
  echo "Pass it explicitly: $0 ${ENV} [tag] /path/to/spring-petclinic-microservices" >&2
  exit 1
fi

command -v aws >/dev/null 2>&1 || { echo "aws CLI not found in PATH" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "docker not found in PATH" >&2; exit 1; }
docker buildx version >/dev/null 2>&1 || { echo "docker buildx not available" >&2; exit 1; }

if [[ -n "${ARG_TAG}" ]]; then
  TAG="${ARG_TAG}"
else
  TAG="$(git -C "${APP_REPO_DIR}" rev-parse --short=7 HEAD)" \
    || { echo "Error: couldn't derive a tag from git — pass one explicitly." >&2; exit 1; }
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Module -> ECR repo suffix -> real runtime port. Ports come from
# docs/technical-spec.md#application-services — NOT from each module's
# pom.xml docker.image.exposed.port property. Several of those are wrong
# (api-gateway, vets-service, and genai-service all show 8081, a
# copy-paste leftover; visits-service uses a mistyped property name and
# silently falls back to the parent's 9090). See docs/technical-spec.md#docker-build.
MODULES=(spring-petclinic-config-server spring-petclinic-discovery-server spring-petclinic-api-gateway spring-petclinic-customers-service spring-petclinic-visits-service spring-petclinic-vets-service spring-petclinic-genai-service spring-petclinic-admin-server)
REPOS=(config-server discovery-server api-gateway customers-service visits-service vets-service genai-service admin-server)
PORTS=(8888 8761 8080 8081 8082 8083 8084 9090)

echo "============================================"
echo "  Building and pushing Petclinic images"
echo "  Environment: ${ENV}"
echo "  Tag:         ${TAG}"
echo "  Registry:    ${REGISTRY}"
echo "  App repo:    ${APP_REPO_DIR}"
echo "============================================"
echo ""

# --- [1/3] Maven: JARs only, no docker profile ------------------------------
echo "[1/3] Building JARs with Maven (mvnw clean package — no -P buildDocker)..."
( cd "${APP_REPO_DIR}" && ./mvnw -q clean package )

APP_VERSION="$(cd "${APP_REPO_DIR}" && ./mvnw -q help:evaluate -Dexpression=project.version -DforceStdout)"
echo "  -> app version: ${APP_VERSION}"
echo ""

# --- [2/3] ECR login ---------------------------------------------------------
echo "[2/3] Authenticating to ECR..."
"${SCRIPT_DIR}/ecr-login.sh" --region "${REGION}"
echo ""

# --- [3/3] docker buildx: one linux/arm64 image per service, pushed to ECR --
echo "[3/3] Building and pushing linux/arm64 images..."

# docker-container driver bundles QEMU emulation for cross-platform builds —
# the same effect as docker/setup-qemu-action + docker/setup-buildx-action
# in the CI equivalent of this script (PETPLAT-49).
if ! docker buildx inspect petclinic-builder >/dev/null 2>&1; then
  docker buildx create --name petclinic-builder --driver docker-container --use >/dev/null
else
  docker buildx use petclinic-builder
fi
docker buildx inspect --bootstrap >/dev/null

# Pre-push scan gate, per CLAUDE.md's CI/CD convention ("Trivy scan after
# Docker build, fail on CRITICAL CVEs"). When trivy is available: build
# locally first (--load), scan, and only push a clean image. When it isn't,
# fall back to build+push in one step and rely on ECR's scan-on-push
# (asynchronous, detective rather than preventive) — see
# docs/runbooks/ecr-image-build-push.md.
HAVE_TRIVY=0
command -v trivy >/dev/null 2>&1 && HAVE_TRIVY=1
if [[ "${HAVE_TRIVY}" -eq 0 ]]; then
  echo "  (trivy not found in PATH — skipping pre-push scan; ECR scan-on-push still runs after push)" >&2
fi

for i in "${!MODULES[@]}"; do
  MODULE="${MODULES[$i]}"
  REPO="${REPOS[$i]}"
  PORT="${PORTS[$i]}"
  ARTIFACT_NAME="${MODULE}-${APP_VERSION}"
  IMAGE="${REGISTRY}/petclinic-${ENV}/${REPO}:${TAG}"

  echo "  -> ${REPO} (port ${PORT}, artifact ${ARTIFACT_NAME}.jar)"

  if [[ "${HAVE_TRIVY}" -eq 1 ]]; then
    docker buildx build \
      --platform linux/arm64 \
      -f "${APP_REPO_DIR}/docker/Dockerfile" \
      --build-arg ARTIFACT_NAME="${ARTIFACT_NAME}" \
      --build-arg EXPOSED_PORT="${PORT}" \
      -t "${IMAGE}" \
      --load \
      "${APP_REPO_DIR}/${MODULE}/target"

    echo "     scanning with trivy (fail on CRITICAL)..."
    trivy image --severity CRITICAL --exit-code 1 --quiet "${IMAGE}"

    docker push "${IMAGE}"
  else
    docker buildx build \
      --platform linux/arm64 \
      -f "${APP_REPO_DIR}/docker/Dockerfile" \
      --build-arg ARTIFACT_NAME="${ARTIFACT_NAME}" \
      --build-arg EXPOSED_PORT="${PORT}" \
      -t "${IMAGE}" \
      --push \
      "${APP_REPO_DIR}/${MODULE}/target"
  fi
done

echo ""
echo "============================================"
echo "  Done. Pushed ${#MODULES[@]} images tagged '${TAG}' to petclinic-${ENV}/"
echo ""
echo "  Verify:"
echo "    aws ecr describe-images --repository-name petclinic-${ENV}/customers-service --region ${REGION}"
echo "  Console:"
echo "    https://${REGION}.console.aws.amazon.com/ecr/repositories?region=${REGION}"
echo "============================================"
