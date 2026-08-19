# Cross-platform build environments, applied to every pex_binary/docker_image
# by default via __defaults__ below.
#
# The EKS node group and CI runners are linux/x86_64, but `pants package` can
# run on an Apple Silicon Mac. Without forcing the resolve onto linux/x86_64
# the PEX bundles macOS wheels and the Dockerfile's venv step fails with
# "Failed to find compatible interpreter". See CLAUDE.md for the full trap.
local_environment(
    name="local_linux",
    compatible_platforms=["linux_x86_64"],
    # Matches natively on any linux/x86_64 machine (every CI runner); only a
    # non-matching host falls back to the docker_environment below.
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

__defaults__(
    {
        pex_binary: dict(environment="local_linux"),
        docker_image: dict(build_platform=["linux/amd64"]),
    }
)
