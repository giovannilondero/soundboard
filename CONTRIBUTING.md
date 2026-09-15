# Contributing

Build and install from source with `make install`; `make restart` rebuilds and restarts the
daemon after code changes. See the README for requirements and configuration.

## Releasing

Tagging is the whole process: `.github/workflows/release.yml` builds the universal binary on macOS 14,
ad-hoc signs it, and attaches the tarball and its `.sha256` to the GitHub release.

```sh
git tag -a v1.0.0 -m "v1.0.0" && git push origin v1.0.0
```

`workflow_dispatch` re-runs it for an existing tag, replacing the attached files.
