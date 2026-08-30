# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.9] — 2026-06-28

### Fixed
- Gemini role decoding now recognizes `"model"` as an assistant role (previously silently dropped)

## [0.0.8] — 2026-06-28

### Fixed
- GPT `chat_message_decoder` no longer crashes the BEAM process on unrecognized roles; returns a proper decode error instead

## [0.0.7] — 2026-06-28

### Added
- Mise task `tests:integration` for running integration tests with API keys from `.env`
- Integration test for GPT with system instructions
- CHANGELOG.md

### Fixed
- GPT client now sends `system_instruction` as the `instructions` field in OpenAI Responses API requests (previously the parameter was silently discarded)

## [0.0.6] — 2025-09-10

### Added
- Anthropic Claude support (`client.Claude`)
- Mise configuration for tool version management

### Changed
- Integration tests can be conditionally run via `RUN_INTEGRATION_TESTS` env var

### Fixed
- Compilation issues

## [0.0.5] — 2025-09-08

### Added
- Helper functions `messages.user()` and `messages.model()` for constructing chat messages
- Fluent builder pattern via `client.request()`, `client.with_message()`, `client.completion()`

## [0.0.4] — 2025-09-07

### Added
- System instruction support for Gemini via `client.with_system_instruction()`

## [0.0.3] — 2025-09-06

### Added
- OpenAI GPT support (`client.GPT`)
- Installation instructions in README

## [0.0.2] — 2025-09-05

### Changed
- Made internal types opaque for better encapsulation

## [0.0.1] — 2025-09-05

### Added
- Initial release
- Google Gemini support (`client.Gemini`)
- Basic chat completion with `ChatMessage` and `Completion` types
- Integration tests for Gemini
- MIT License

[Unreleased]: https://github.com/Endi1/llmgleam/compare/v0.0.9...HEAD
[0.0.9]: https://github.com/Endi1/llmgleam/compare/v0.0.8...v0.0.9
[0.0.8]: https://github.com/Endi1/llmgleam/compare/v0.0.7...v0.0.8
[0.0.7]: https://github.com/Endi1/llmgleam/compare/v0.0.6...v0.0.7
[0.0.6]: https://github.com/Endi1/llmgleam/compare/v0.0.5...v0.0.6
[0.0.5]: https://github.com/Endi1/llmgleam/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/Endi1/llmgleam/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/Endi1/llmgleam/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/Endi1/llmgleam/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/Endi1/llmgleam/releases/tag/v0.0.1
