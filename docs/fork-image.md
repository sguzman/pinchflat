# Fork image workflow

This fork builds its own image through **Build fork image (manual)**.

## Publishing

1. Merge a tested change into `master`.
2. In the fork's GitHub **Actions** tab, select **Build fork image (manual)**.
3. Use **Run workflow**, selecting `master`, when a new image is actually needed.
4. After the workflow succeeds, the image is `ghcr.io/sguzman/pinchflat:dev`.

The workflow is **manual-only**. Ordinary pushes, pull requests, and releases cannot trigger it. It builds for `linux/amd64`, authenticates with the built-in `GITHUB_TOKEN`, and publishes solely to the fork's GitHub Container Registry namespace. No Docker Hub credentials are needed.

The legacy `docker_release.yml` workflow comes from upstream and targets the original maintainer's Docker Hub repository. **Keep that workflow disabled**; do not re-enable it for this fork.

GitHub Container Registry package visibility is separate from repository visibility. When the first image is published, check whether the new package is private before expecting unauthenticated `docker pull` to work. Publish visibility deliberately.

## Deployment safety

This workflow does **not** access a local Docker engine, restart containers, or copy any media. It only builds and publishes an image to GHCR.

Before replacing the running Pinchflat container:

- Inspect its existing image, environment variables, mount paths, port mappings, and restart policy.
- Back up the current `/config` data, including the SQLite database.
- Do **not** touch or wipe `/downloads`; preserve existing `.part` files for resumable downloads.
- Prefer a separate test instance with separate config and media mounts before switching production.
- Keep `YT_DLP_WORKER_CONCURRENCY=1` for the production instance.

The production Dockerfile fetches yt-dlp's latest Linux release during each image build; there is no need to rely on an `yt-dlp -U` change inside a running container, which can disappear after recreation.
