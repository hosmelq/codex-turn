# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased](https://github.com/hosmelq/codex-turn/compare/v1.0.1...HEAD)

### Fixed

- Resolve project display names from Git repository metadata when sessions run from codename-based clone paths.
- Avoid rendering raw JSON payloads as thread titles by extracting readable summary fields from structured (including truncated) responses.

## [v1.0.1](https://github.com/hosmelq/codex-turn/compare/v1.0.0...v1.0.1) - 2026-02-28

### Fixed

- Preserve release tag in Sparkle appcast download URLs so update downloads resolve correctly.
- Prevent the history scanner from treating response item IDs as session IDs when session metadata is missing.

## [v1.0.0](https://github.com/hosmelq/codex-turn/releases/tag/v1.0.0) - 2026-02-27

Initial release.
