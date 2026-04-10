defmodule Mix.Tasks.Docs.Watch do
  @shortdoc "Builds docs, serves them locally, and rebuilds on file changes"
  @moduledoc """
  Watches source files and rebuilds documentation on changes,
  serving the result with live reload.

      $ mix docs.watch

  ## Options

    * `--port` / `-p` - port to serve on (default: 4001)
    * `--no-open` - don't open the browser automatically

  """

  use Mix.Task

  @default_port 4001
  @debounce_ms 500

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [port: :integer, no_open: :boolean],
        aliases: [p: :port]
      )

    port = opts[:port] || @default_port
    Application.ensure_all_started(:file_system)

    docs_config =
      try do
        resolve_docs_config()
      catch
        _, _ -> []
      end

    doc_dir = docs_config[:output] || "doc"
    dirs = watched_dirs(docs_config)

    info("Building docs...")

    case rebuild_docs() do
      :ok ->
        :ok

      {:error, output} ->
        Mix.shell().error(output)
        info("Will retry on file changes")
    end

    {:ok, _} = MixWatchDocs.Server.start_link(port: port, doc_dir: doc_dir)
    {:ok, _} = MixWatchDocs.Watcher.start_link(dirs: dirs, debounce_ms: @debounce_ms)

    url = "http://localhost:#{port}"
    info("Serving docs at #{url}")
    info("Watching #{Enum.map_join(dirs, ", ", &Path.relative_to_cwd/1)} for changes")

    unless opts[:no_open], do: open_browser(url)

    Process.sleep(:infinity)
  end

  @doc false
  def rebuild do
    info("Rebuilding...")

    case rebuild_docs() do
      :ok ->
        MixWatchDocs.Server.reload()
        info("Done.")

      {:error, output} ->
        Mix.shell().error(output)
    end
  end

  defp rebuild_docs do
    case System.cmd("mix", ["docs"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> {:error, String.trim(output)}
    end
  end

  defp resolve_docs_config do
    case Mix.Project.config()[:docs] do
      fun when is_function(fun, 0) -> fun.()
      config when is_list(config) -> config
      _ -> []
    end
  end

  defp watched_dirs(docs_config) do
    source_dirs = Mix.Project.config()[:elixirc_paths] || ["lib"]

    extra_dirs =
      (docs_config[:extras] || [])
      |> Enum.flat_map(fn
        {path, _} when is_binary(path) -> [Path.dirname(path)]
        path when is_binary(path) -> [Path.dirname(path)]
        _ -> []
      end)
      |> Enum.reject(&(&1 == "."))

    (source_dirs ++ extra_dirs)
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
    |> Enum.filter(&File.dir?/1)
    |> remove_subdirs()
  end

  defp remove_subdirs(dirs) do
    Enum.reject(dirs, fn dir ->
      Enum.any?(dirs, fn other ->
        other != dir and String.starts_with?(dir, other <> "/")
      end)
    end)
  end

  defp info(msg), do: Mix.shell().info("[docs.watch] #{msg}")

  defp open_browser(url) do
    case :os.type() do
      {:unix, :darwin} -> System.cmd("open", [url])
      {:unix, _} -> System.cmd("xdg-open", [url])
      {:win32, _} -> System.cmd("cmd", ["/c", "start", url])
    end
  end
end
