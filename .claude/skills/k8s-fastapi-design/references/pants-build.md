# Pants build gotchas specific to this project

## Resolve and source-root configuration

Any `python_sources()`/`python_tests()` target that doesn't set `resolve=` explicitly falls back to Pants's own hardcoded default resolve name, which doesn't exist as an actual resolve in this project -- set `[python].default_resolve` to the project's real resolve name so newer directories don't need to state it individually, and so `lint`/`test` don't fail with an unrecognized-resolve error the moment a new source directory is added without a resolve set on it.

Every top-level source directory needs its own entry in `[source].root_patterns` -- a second top-level directory (for example a `tests/` sibling of `src/`) that isn't listed there has no source root at all as far as Pants is concerned, and `pants test ::` fails with a source-root error even though the target's own BUILD file is set up correctly.

## Cross-platform Docker builds

`pants package` builds a `pex_binary` by resolving dependencies for whatever machine is actually running the command -- not for whatever machine the resulting Docker image will run on. If a developer's machine has a different CPU architecture than the EKS node group (for example an Apple Silicon Mac building for x86_64 nodes), the packaged PEX ends up bundling wheels for the wrong platform, and the Dockerfile step that unpacks the PEX into a venv (which runs inside a Linux container matching the *target* architecture) fails with something like "Failed to find compatible interpreter" or "this pex had no '<package>' distributions" -- the PEX genuinely never had a wheel for the platform it's being asked to run on.

Two ways to fix this, in order of robustness:

1. **A `docker_environment`** (via Pants's environments-preview feature) that actually executes the resolve/build on the target architecture -- natively when the machine already matches, falling back to Docker-based emulation (a `local_environment` with `fallback_environment` pointing at the `docker_environment`) when it doesn't. This handles anything requiring compilation, not just prebuilt wheels, and is the more correct long-term approach.
2. **A `complete_platforms` file** on the `pex_binary` target, declaring the target platform's tags so Pants fetches the right prebuilt wheels directly from the package index without executing anything on that platform. Simpler, but only works when every dependency already ships a prebuilt wheel for the target platform -- anything that only ships an sdist for that platform can't be resolved this way.

Either way, the `docker_image`'s own `build_platform` field needs to match the same target architecture (mapping to `docker build --platform`), so the actual image build agrees with what the `pex_binary` bundled -- otherwise the final `docker build` step can default to the *host* machine's architecture regardless of what the PEX contains, reproducing the same failure one layer up.

Repo-wide target defaults (which build environment a `pex_binary` uses, which platform a `docker_image` builds for) are best set once via `__defaults__` in the root `BUILD` file rather than repeated on every target -- `__defaults__` cascades down to every BUILD file in the directory tree beneath it, and can be overridden locally in a subdirectory if a specific target genuinely needs something different.

## Docker credential helper visibility

Pants runs `docker build` in its own sandboxed subprocess, which does not automatically inherit the full `PATH` of the interactive shell that invoked `pants`. On a machine where Docker's credential store is configured to shell out to a helper binary (for example one installed by a desktop Docker client), that helper can resolve fine in a normal terminal but fail inside Pants's sandbox with an "executable file not found in $PATH" error -- the fix is passing the host's `PATH` through explicitly via `[docker].env_vars`, not reinstalling or reconfiguring anything about Docker itself.

## Lockfile is committed, not regenerated in CI

The dependency lockfile is generated once (via Pants's own lockfile-generation command) and committed to git -- CI has no step that regenerates it, so it must already be present for any lint/test/package command to resolve dependencies at all. Regenerate and recommit it whenever the underlying requirements file changes; don't expect CI to do this automatically.
