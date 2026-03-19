# Versioning Proposal

## Summary

This sandbox template uses Semantic Versioning and treats the git tag as the single source of truth for release versioning.

The starting release for this repository is `v0.1.0`.

The goal is to keep versioning simple and portable across local development, CI, Yocto builds, and Rust applications:

- release versions come from annotated git tags
- non-release builds derive a development version from git state
- Cargo, Yocto, and runtime reporting all consume the same version information

## Versioning Standard

We follow [Semantic Versioning 2.0.0](https://semver.org/).

Version format:

- stable releases: `vMAJOR.MINOR.PATCH`
- pre-releases: `vMAJOR.MINOR.PATCH-alpha.N`, `vMAJOR.MINOR.PATCH-beta.N`, `vMAJOR.MINOR.PATCH-rc.N`

Examples:

- `v0.1.0`
- `v0.2.0-alpha.1`
- `v1.0.0-rc.2`

Precedence follows semver rules:

$$
0.1.0\text{-alpha.1} < 0.1.0\text{-beta.1} < 0.1.0\text{-rc.1} < 0.1.0
$$

## Source Of Truth

Git tags are the only source of truth for release versions.

Rules:

1. No system independently invents a release version.
2. CI may derive build-time strings from the tag, but it does not choose the release version.
3. Yocto consumes the version; it does not define it.
4. Rust crates consume the version from a shared workspace definition or injected build-time variable.

## Starting Version

The initial release for this sandbox template is:

- `v0.1.0`

This indicates:

- the repository is usable as a template baseline
- the interfaces and layout may still evolve before `v1.0.0`
- breaking changes are still acceptable while the project remains in the `0.x` series

## Version String Conventions

Different parts of the system need slightly different version representations.

| Layer | Format | Example |
|-------|--------|---------|
| Git tag | Semver with `v` prefix | `v0.1.0` |
| Cargo.toml / `CARGO_PKG_VERSION` | Semver without `v` | `0.1.0` |
| Yocto `PV` | Semver without `v` | `0.1.0` |
| Runtime build string | Semver plus optional metadata | `0.1.0-alpha.2+17.gabcdef0` |

The `v` prefix exists only at the git tag boundary.

Build metadata after `+` is optional and should be used for traceability only. It must not change release precedence.

## Release Tags

Release builds are created from annotated tags.

Examples:

```bash
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

For pre-releases:

```bash
git tag -a v0.2.0-rc.1 -m "Release v0.2.0-rc.1"
git push origin v0.2.0-rc.1
```

Recommended policy:

- use annotated tags, not lightweight tags
- keep release tags immutable
- build release artifacts only from tags

## Local Development Builds

Local builds are not releases unless they are built from a release tag.

When no explicit version is supplied by CI, local builds should derive a development version from git via a shared Just recipe:

```bash
eval "$(just git::version-env)"
export VERSION BUILD_VERSION
```

For a fast baseline CI pass (non-release), run:

```bash
just ci::preflight
```

Examples:

- on tag `v0.1.0-alpha.2`: `VERSION=0.1.0-alpha.2`, `BUILD_VERSION=0.1.0-alpha.2+0.gabcdef0`
- five commits after `v0.1.0-alpha.2`: `VERSION=0.1.0-alpha.2`, `BUILD_VERSION=0.1.0-alpha.2+5.gabcdef0`
- no matching tags yet: `VERSION=0.1.0-alpha`, `BUILD_VERSION=0.1.0-alpha+gabcdef0`

These values are useful for debugging and traceability, but they are not release versions.

## Rust Guidance

Rust applications in this template should use workspace-level version inheritance so the version is defined once.

Recommended workspace pattern:

```toml
[workspace.package]
version = "0.1.0"
edition = "2024"
```

Recommended crate pattern:

```toml
[package]
name = "example-app"
version.workspace = true
edition.workspace = true
```

Benefits:

- one place to manage the Cargo-visible version
- no version drift across crates
- `CARGO_PKG_VERSION` stays consistent across the workspace

For runtime reporting, the application may expose:

- `CARGO_PKG_VERSION` as the default version
- an optional CI-provided full build string for `--version` output

## Yocto Guidance

Yocto should consume the version from the external build environment.

Recommended pattern:

- pass the version from CI or the calling shell into kas/bitbake explicitly
- set recipe `PV` from that passed-in version
- pin application source with a CI-provided commit SHA (for example `SOURCE_REV`)
- avoid hard-coding release versions in recipes

Example:

```bitbake
PV = "${@d.getVar('VERSION') or '0.1.0-alpha'}"
```

If version variables are passed through the environment, do it explicitly in kas/local configuration rather than relying on implicit shell inheritance.

For immutable release builds, ensure:

1. tag version matches workspace version
2. Yocto app recipes build from an explicit commit SHA (not a live working tree)

## CI Guidance

CI should derive version variables from the pushed tag and export them for all downstream build steps.

Recommended variables:

1. `VERSION`
   semver only, without the `v` prefix, for Cargo and Yocto
2. `BUILD_VERSION`
   full runtime/display string, optionally including build metadata

Example:

- tag: `v0.1.0-alpha.2`
- `VERSION=0.1.0-alpha.2`
- `BUILD_VERSION=0.1.0-alpha.2+17.gabcdef0`

For tagged releases, CI should additionally enforce:

1. the tag is annotated
2. the tag version (without `v`) matches `[workspace.package].version` in `apps/Cargo.toml`

Template release-candidate command:

```bash
just release-candidate 1.2.3
```

In this template, RC flow runs:

1. derive next candidate tag (`v1.2.3-rc.N`)
2. update workspace version to `1.2.3-rc.N`
3. create dedicated release-candidate commit and annotated RC tag
4. push branch + RC tag
5. build and publish canonical RC artifacts from the RC tag

Promotion is a separate manual workflow that:

1. verifies candidate artifacts and checksums
2. promotes artifacts atomically to stable release paths (no rebuild)
3. creates or verifies stable tag `v1.2.3` at the candidate commit
4. publishes GitHub release metadata

## End-To-End Flow

```text
just release-candidate 1.2.3
  -> creates/pushes v1.2.3-rc.N
  -> RC CI triggered from candidate tag
  -> VERSION=1.2.3-rc.N
  -> BUILD_VERSION=1.2.3-rc.N+0.gabcdef0
  -> kas/bitbake receives VERSION
  -> Yocto recipes set PV from VERSION
  -> Rust workspace uses version 1.2.3-rc.N
  -> runtime can report BUILD_VERSION
promote-candidate workflow
  -> verifies candidate checksums and manifest
  -> atomically copies candidate artifacts to stable release path
  -> ensures stable tag points to same commit
  -> no rebuild occurs
```

## Verification

For a release built from tag `v0.1.0`, the expected values are:

| Check | Expected value |
|-------|----------------|
| Git tag | `v0.1.0` |
| Cargo package version | `0.1.0` |
| Yocto `PV` | `0.1.0` |
| Runtime version output | `0.1.0` or `0.1.0+<build-metadata>` |

For a local non-release build, the expected values are:

| Check | Expected value |
|-------|----------------|
| Git tag | none required |
| Derived version | `0.1.0-alpha` |
| Release artifact status | not a release |

## Recommended Policy

1. Start the repository at `v0.1.0`.
2. Use annotated git tags for all releases.
3. Strip the `v` prefix before passing versions into Cargo and Yocto.
4. Keep one Cargo-visible version at the workspace root.
5. Keep Yocto `PV` aligned with the same semver value.
6. Use build metadata only for runtime display and traceability.

## Open Questions

Current default decisions in this template:

1. Keep push/PR validation CI enabled, and add manual profile builds (`dev`, `test`).
2. Build immutable candidate artifacts from RC tags only.
3. Promote to stable without rebuild.
4. Allow local/manual profile artifact publication into structured paths.
