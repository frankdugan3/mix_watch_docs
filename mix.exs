defmodule MixWatchDocs.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/frankdugan3/mix_watch_docs"

  def project do
    [
      app: :mix_watch_docs,
      version: @version,
      elixir: "~> 1.19",
      deps: deps(),
      description:
        "A Mix task that watches source files, rebuilds docs on changes, and serves them with live reload.",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  defp deps do
    [
      {:file_system, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:git_ops, "~> 2.9", only: :dev}
    ]
  end

  defp package do
    [
      maintainers: ["Frank Polasek Dugan III"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        {"README.md", title: "Home"},
        {"CHANGELOG.md", title: "Changelog"}
      ]
    ]
  end
end
