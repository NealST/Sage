# Vendored MarkdownEngine

This directory contains the dependency-free `MarkdownEngine` core from:

- Upstream: <https://github.com/nodes-app/swift-markdown-engine>
- License: Apache License 2.0 (see `LICENSE`)
- Imported: 2026-08-24

Sage owns and builds this source locally. The package manifest was changed to
omit the optional `MarkdownEngineCodeBlocks` and `MarkdownEngineLatex` adapter
targets and their remote dependencies. The core engine source and upstream
tests were copied without modification.

When updating the vendored source, retain the upstream license and record the
upstream revision and local modifications here.
