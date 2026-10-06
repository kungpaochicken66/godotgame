# Source Upload

The user authorized uploading this repository to an existing SSH account and project directory on 2026-10-06. The destination is operational handoff information, supplied separately to the operator; it is not embedded in product code or screenshots. No credentials are stored in the repository.

## Scope

Transfer the preview, documents, generated concept assets, validation script and initialized Git metadata. Do not start a public server, change firewall rules, install dependencies, buy services, create a remote Git hosting project or publish an iPad build.

## Procedure

1. Connect using the authorized SSH account without printing or copying private key material.
2. Inspect the destination. If it is not empty, compare existing files before overwriting or removing anything.
3. Run local checks and inspect the preview.
4. Initialize Git with `main` if there is no existing repository. Do not create a commit or push without explicit authorization.
5. Copy the repository with `rsync`, excluding local caches and operating-system metadata. Do not use `--delete`.
6. Compare SHA-256 checksums for every transferred file, verify Git's branch and run the dependency-free checks remotely.

An uploaded source tree is not a deployed game. This task does not start any persistent service on the destination.
