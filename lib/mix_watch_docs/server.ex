defmodule MixWatchDocs.Server do
  @moduledoc false
  use GenServer

  @reload_script ~s[<script>(function(){var s=new EventSource("/__reload");s.onmessage=function(){location.reload()}})()</script>]

  @mime %{
    ".html" => "text/html; charset=utf-8",
    ".css" => "text/css",
    ".js" => "application/javascript",
    ".json" => "application/json",
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".gif" => "image/gif",
    ".svg" => "image/svg+xml",
    ".ico" => "image/x-icon",
    ".woff" => "font/woff",
    ".woff2" => "font/woff2",
    ".ttf" => "font/ttf",
    ".eot" => "application/vnd.ms-fontobject",
    ".xml" => "application/xml",
    ".txt" => "text/plain"
  }

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def reload, do: GenServer.cast(__MODULE__, :reload)

  @impl true
  def init(opts) do
    port = opts[:port]
    doc_dir = opts[:doc_dir]

    {:ok, listen} =
      :gen_tcp.listen(port, [:binary, packet: :http_bin, active: false, reuseaddr: true])

    spawn_link(fn -> accept_loop(listen, doc_dir) end)
    {:ok, %{listen: listen, doc_dir: doc_dir, sse_clients: MapSet.new()}}
  end

  @impl true
  def handle_cast(:reload, state) do
    alive = MapSet.filter(state.sse_clients, &Process.alive?/1)
    Enum.each(alive, &send(&1, :reload))
    {:noreply, %{state | sse_clients: alive}}
  end

  @impl true
  def handle_call({:register_sse, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | sse_clients: MapSet.put(state.sse_clients, pid)}}
  end

  @impl true
  def handle_info({:DOWN, _, :process, pid, _}, state) do
    {:noreply, %{state | sse_clients: MapSet.delete(state.sse_clients, pid)}}
  end

  defp accept_loop(listen, doc_dir) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        spawn(fn -> handle_request(socket, doc_dir) end)
        accept_loop(listen, doc_dir)

      {:error, :closed} ->
        :ok
    end
  end

  defp handle_request(socket, doc_dir) do
    with {:ok, {:http_request, :GET, {:abs_path, raw_path}, _}} <- :gen_tcp.recv(socket, 0, 5000) do
      consume_headers(socket)
      :inet.setopts(socket, packet: :raw)
      path = raw_path |> URI.decode() |> String.split("?") |> hd()

      if path == "/__reload",
        do: serve_sse(socket),
        else: serve_file(socket, path, doc_dir)
    else
      _ -> :gen_tcp.close(socket)
    end
  end

  defp consume_headers(socket) do
    case :gen_tcp.recv(socket, 0, 5000) do
      {:ok, {:http_header, _, _, _, _}} -> consume_headers(socket)
      {:ok, :http_eoh} -> :ok
      _ -> :ok
    end
  end

  defp serve_sse(socket) do
    :gen_tcp.send(socket, [
      "HTTP/1.1 200 OK\r\n",
      "Content-Type: text/event-stream\r\n",
      "Cache-Control: no-cache\r\n",
      "Connection: keep-alive\r\n\r\n"
    ])

    GenServer.call(__MODULE__, {:register_sse, self()})
    sse_loop(socket)
  end

  defp sse_loop(socket) do
    receive do
      :reload ->
        case :gen_tcp.send(socket, "data: reload\n\n") do
          :ok -> sse_loop(socket)
          _ -> :gen_tcp.close(socket)
        end
    after
      30_000 ->
        case :gen_tcp.send(socket, ": ping\n\n") do
          :ok -> sse_loop(socket)
          _ -> :gen_tcp.close(socket)
        end
    end
  end

  defp serve_file(socket, path, doc_dir) do
    file_path = resolve_path(path, doc_dir)

    case File.read(file_path) do
      {:ok, body} ->
        body = maybe_inject_reload(body, file_path)
        mime = Map.get(@mime, Path.extname(file_path), "application/octet-stream")

        :gen_tcp.send(socket, [
          "HTTP/1.1 200 OK\r\nContent-Type: #{mime}\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n",
          body
        ])

      {:error, _} ->
        :gen_tcp.send(
          socket,
          "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\nConnection: close\r\n\r\nNot Found"
        )
    end

    :gen_tcp.close(socket)
  end

  defp resolve_path("/", doc_dir), do: Path.join(doc_dir, "index.html")

  defp resolve_path(path, doc_dir) do
    clean = path |> Path.expand("/") |> String.trim_leading("/")
    full = Path.join(doc_dir, clean)

    cond do
      File.regular?(full) -> full
      File.dir?(full) -> Path.join(full, "index.html")
      File.regular?(full <> ".html") -> full <> ".html"
      true -> full
    end
  end

  defp maybe_inject_reload(body, path) do
    if String.ends_with?(path, ".html"),
      do: String.replace(body, "</body>", @reload_script <> "</body>"),
      else: body
  end
end
