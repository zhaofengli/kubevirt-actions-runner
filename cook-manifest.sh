#!/usr/bin/env bash
set -euo pipefail

IMAGE=kubevirt-actions-runner
TARGET=$1

nix build .#image-amd64 -L -o amd64-image
nix build .#image-arm64 -L -o arm64-image

docker load <amd64-image
docker tag ${IMAGE}:main ${TARGET}-amd64
docker load <arm64-image
docker tag ${IMAGE}:main ${TARGET}-arm64
docker push ${TARGET}-amd64
docker push ${TARGET}-arm64
docker manifest create ${TARGET} \
	--amend ${TARGET}-amd64 \
	--amend ${TARGET}-arm64
docker manifest push ${TARGET}
