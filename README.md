# github-workflows

Github workflows to be used across the organization. They need to be in a public repo so that they are available in both private and public repos.

## Check action pins

Call `.github/workflows/check-action-pins.yml` by a reviewed full commit SHA from
a workflow that runs on `pull_request`, `merge_group`, and pushes to the default
branch. Grant the caller `contents: read`; no other permissions or secrets are
needed. The check parses tracked workflow and action YAML, including composite
actions, and rejects external references without a 40-character commit SHA.
Local actions remain local; Docker actions must use a `sha256` image digest.

The checker uses the Ruby and YAML parser bundled with `ubuntu-latest` and does
not install dependencies. Run its regression cases with:

```sh
ruby .github/scripts/check-action-pins_test.rb
```

## Update pinned actions

Enable the `github-actions` ecosystem in Dependabot. It opens reviewable PRs for
SHA-pinned actions and reusable workflows and updates same-line version comments.
Keep the original version beside each pin, for example:

```yaml
uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
```

Before merging an update, verify that the commit belongs to the upstream
repository, matches the intended release, and has been reviewed. Inspect nested
actions and runtime downloads as well as the action wrapper. Keep write token
permissions on the jobs that need them and pass secrets only to the steps that
consume them. Do not auto-merge changes to credential-bearing workflows.

See [GitHub's Dependabot documentation](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories#github-actions)
for SHA updates and version comments.

## What action pinning covers

Pinning an action fixes its repository contents. It does not fix runner images,
toolchain channels, release assets, package registries, or container base images
that the action downloads. The direct-reference check does not inspect third-party
action internals. The following source review on 2026-11-09 records remaining
transitive inputs in commonly used credential-bearing actions:

| Pinned action source | Remaining runtime input |
| --- | --- |
| [Claude Code action](https://github.com/anthropics/claude-code-action/blob/4fa93a88de49bbef68b10eb15aabedf28ca0e1ed/action.yml) | Its nested Bun action is SHA-pinned, but it downloads Bun and installs production npm dependencies at runtime. The OAuth credential remains available to the Claude action. |
| [Push to another repository](https://github.com/cpina/github-action-push-to-another-repository/blob/55306faa4ed53b815ae49e564af8cfb359d32ae2/Dockerfile) | Builds from mutable `alpine:3.20` and installs packages from Alpine repositories before handling the deploy key. |
| [Install nextest](https://github.com/taiki-e/install-action/blob/7c48f0a661edab95fdc666d1526d9ef945205245/action.yml), [install cargo-llvm-cov](https://github.com/taiki-e/install-action/blob/3f7c3597aa4e6da3f315e128de702ce61e7b2877/action.yml) | Downloads the requested tool at runtime, with checksum verification enabled and a `cargo-binstall` fallback. A pinned action does not pin a tool version omitted by the caller. |
| [Foundry toolchain](https://github.com/foundry-rs/foundry-toolchain/blob/dba66c27052e63476d886f22216e119ba7e615bf/src/index.ts) | Pins its installer script but resolves the requested Foundry toolchain at runtime. `nightly` and `stable` remain moving channels. |
| [Codecov](https://github.com/codecov/codecov-action/blob/ab904c41d6ece82784817410c45d8b8c02684457/src/index.ts) | Downloads an uploader from Codecov; an omitted uploader version resolves to latest. The action validates downloaded checksums/signatures. |
| [Docker Buildx setup](https://github.com/docker/setup-buildx-action/blob/f87e5991a6d7451dcb8d9637bfbc97413f497069/src/main.ts) | Can download Buildx with a default `latest` version; its builder also depends on the selected BuildKit image. |

Review these inputs when updating or expanding secret-bearing workflows. Pin
tool versions and image digests separately when reproducible execution is needed.
Step-scoped secrets reduce direct environment exposure; they do not isolate a
later secret-bearing step from earlier code in the same job.
