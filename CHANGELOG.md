# Changelog

## [0.1.1] - 2026-04-01

### Fixed

- Pin compose image name to `app_name` so it's reused across projects (#12).
  Without an explicit image key, Docker Compose derived the image name from the
  project name, causing a full rebuild on every `aircon up` invocation.

## [0.1.0] - 2026-04-01

- Initial release
