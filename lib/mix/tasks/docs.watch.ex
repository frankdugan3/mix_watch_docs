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
    Mix.Task.run("compile")

    docs_config = resolve_docs_config()
    doc_dir = docs_config[:output] || "doc"
    paths_fun = fn -> watched_paths(resolve_docs_config()) end
    dirs = paths_fun.()

    info("Building docs...")

    case rebuild_docs() do
      :ok ->
        :ok

      {:error, output} ->
        Mix.shell().error(output)
        info("Will retry on file changes")
    end

    {:ok, _} = MixWatchDocs.Server.start_link(port: port, doc_dir: doc_dir)

    {:ok, _} =
      MixWatchDocs.Watcher.start_link(
        paths_fun: paths_fun,
        debounce_ms: @debounce_ms
      )

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
    try do
      case Mix.Project.config()[:docs] do
        fun when is_function(fun, 0) -> fun.()
        config when is_list(config) -> config
        _ -> []
      end
    catch
      _, _ -> []
    end
  end

  defp watched_paths(docs_config) do
    source_dirs = Mix.Project.config()[:elixirc_paths] || ["lib"]

    extras_paths =
      (docs_config[:extras] || [])
      |> Enum.flat_map(fn
        {path, _} when is_binary(path) -> [path]
        path when is_binary(path) -> [path]
        _ -> []
      end)

    {root_extras, nested_extras} =
      Enum.split_with(extras_paths, &(Path.dirname(&1) == "."))

    dirs =
      (source_dirs ++ Enum.map(nested_extras, &Path.dirname/1))
      |> Enum.map(&Path.expand/1)
      |> Enum.uniq()
      |> Enum.filter(&File.dir?/1)
      |> remove_subdirs()

    root_files =
      ["mix.exs" | Enum.map(root_extras, &resolve_source/1)]
      |> Enum.uniq()
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.expand/1)

    dirs ++ root_files
  end

  defp resolve_source(path) do
    eex = path <> ".eex"
    if File.regular?(eex), do: eex, else: path
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
