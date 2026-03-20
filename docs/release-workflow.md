# Release Candidate And Promotion Workflow

## Purpose

This document describes the operational flow for creating a release candidate (RC) and promoting it to a stable release without rebuilding artifacts.

## Release Candidate Workflow

1. Start from a clean branch.
- Ensure there are no staged or unstaged tracked changes.

2. Cut and push the next RC tag.
- Command:

```bash
just release-candidate <MAJOR.MINOR.PATCH>
```

- Example:

```bash
just release-candidate 1.2.3
```

3. What this command does.
- Computes next tag: `v<MAJOR>.<MINOR>.<PATCH>-rc.N`
- Updates workspace version to `<MAJOR>.<MINOR>.<PATCH>-rc.N`
- Creates a dedicated release commit (`release: vX.Y.Z-rc.N`)
- Creates an annotated RC tag
- Pushes branch and RC tag to `origin`

4. RC CI is triggered automatically.
- Workflow: `.github/workflows/release-candidate.yml`
- Trigger: push of tag matching `v*.*.*-rc.*`
- Runs canonical RC pipeline and publishes artifacts.

5. RC artifact location.
- `artifacts/candidates/<candidate-tag>/<machine>/`

## Promotion To Stable Workflow

1. Validate the RC.
- Review CI summary and artifact integrity (manifest/checksums).

2. Run promotion workflow manually.
- Workflow: `.github/workflows/promote-candidate.yml`
- Trigger: `workflow_dispatch`
- Inputs:
- `candidate_tag` (example: `v1.2.3-rc.1`)
- `release_version` (example: `1.2.3`)
- `machine` (default: `qemux86-64`)

3. What promotion does.
- Verifies candidate tag and commit
- Creates/verifies stable tag `v<release_version>` at the candidate commit
- Promotes artifacts atomically (no rebuild)
- Publishes/updates GitHub Release metadata

4. Stable artifact result.
- Promoted artifacts become available at stable release paths from the promoted candidate.

## Equivalent Local Promotion Command

```bash
just ci::promote-candidate <candidate_tag> <release_version> <machine> origin
```

Example:

```bash
just ci::promote-candidate v1.2.3-rc.1 1.2.3 qemux86-64 origin
```

## Notes

- Use annotated tags for both RC and stable.
- Promotion is intentionally separate from RC build to keep release control explicit.
- Stable promotion should not rebuild binaries; it promotes verified candidate artifacts.
