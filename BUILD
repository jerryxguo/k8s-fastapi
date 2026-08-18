# Cross-platform build environments
# pex_binary/docker_image target by default, instead of being declared and
# left for someone to opt into by hand with `--environment=...`.
#
# Why this exists: this project's EKS node group runs t3.medium
# (linux/x86_64-- see node_instance_types in
# infra/terraform/modules/eks-cluster/variables.tf), and GitHub Actions'
# ubuntu-latest runners are also linux/x86_64. But `pants package
# src/app:docker` can just as easily run on a developer's Apple Silicon Mac
# (macos/arm64). Without forcing the resolve/build itself onto linux/x86_64,
# the pex_binary bundles macOS wheels, and the Dockerfile's
# `PEX_TOOLS=1 ... venv` step (which runs inside a linux container) fails
# with "Failed to find compatible interpreter" -- this is the same failure
# `complete_platforms` used to work around here; this environments setup
# supersedes that (see src/app/BUILD), since it actually executes the
# resolve on real linux/x86_64 rather than just fetching wheel metadata for
# a platform tag.
local_environment(
    name="local_linux",
    compatible_platforms=["linux_x86_64"],
    # On a machine that's already linux/x86_64 (every CI runner), this
    # environment matches directly and Pants just runs natively -- no
    # Docker involved, no slowdown. Only when the *actual* local machine
    # doesn't match (an Apple Silicon Mac) does Pants fall back to the
    # `cross_build` docker_environment below.
    fallback_environment="cross_build",
)

local_environment(
    name="local_macos",
    compatible_platforms=["macos_arm64", "macos_x86_64"],
)

docker_environment(
    name="cross_build",
    platform="linux_x86_64",
    image="pantsbuild/wheel_build_x86_64:v1-568cfc69e",
)

__defaults__({
    pex_binary: dict(environment="local_linux"),
    docker_image: dict(build_platform=["linux/amd64"]),
})
