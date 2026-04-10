# MixWatchDocs

[![Hex.pm](https://img.shields.io/hexpm/v/mix_watch_docs.svg)](https://hex.pm/packages/mix_watch_docs)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/mix_watch_docs)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Mix task that watches your source files, rebuilds documentation on changes, and serves it locally with live reload.

## Installation

Add `mix_watch_docs` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mix_watch_docs, "~> 0.1.0", only: :dev, runtime: false}
  ]
end
```

Requires a documentation generator that provides `mix docs` (e.g., [ExDoc](https://github.com/elixir-lang/ex_doc)).

## Usage

```
$ mix docs.watch
```

Builds your docs, starts a local server with live reload, and watches for source changes to rebuild automatically.

### Options

- `--port` / `-p` - port to serve on (default: 4001)
- `--no-open` - don't open the browser automatically
