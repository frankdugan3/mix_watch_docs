defmodule MixWatchDocs.Watcher do
  @moduledoc false
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    debounce_ms = opts[:debounce_ms] || 500
    paths_fun = opts[:paths_fun]
    fs_pid = start_fs(paths_fun.())

    {:ok,
     %{
       fs_pid: fs_pid,
       paths_fun: paths_fun,
       debounce_ms: debounce_ms,
       timer: nil,
       cooldown: false,
       mix_changed: false
     }}
  end

  @impl true
  def handle_info({:file_event, _, {_, _}}, %{cooldown: true} = state) do
    {:noreply, state}
  end

  def handle_info({:file_event, _, {path, _}}, state) do
    if source_file?(path) do
      if state.timer, do: Process.cancel_timer(state.timer)
      timer = Process.send_after(self(), :rebuild, state.debounce_ms)
      mix_changed = state.mix_changed or Path.basename(path) == "mix.exs"
      {:noreply, %{state | timer: timer, mix_changed: mix_changed}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:file_event, _, :stop}, state) do
    Mix.shell().error("[docs.watch] File watcher stopped")
    {:noreply, state}
  end

  def handle_info(:rebuild, state) do
    Mix.Tasks.Docs.Watch.rebuild()

    fs_pid =
      if state.mix_changed do
        stop_fs(state.fs_pid)
        start_fs(state.paths_fun.())
      else
        state.fs_pid
      end

    Process.send_after(self(), :cooldown_done, state.debounce_ms)

    {:noreply,
     %{state | fs_pid: fs_pid, timer: nil, cooldown: true, mix_changed: false}}
  end

  def handle_info(:cooldown_done, state) do
    {:noreply, %{state | cooldown: false}}
  end

  defp start_fs(paths) do
    {:ok, pid} = FileSystem.start_link(dirs: paths)
    FileSystem.subscribe(pid)
    pid
  end

  defp stop_fs(pid) when is_pid(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
  end

  defp source_file?(path) when is_binary(path) do
    cond do
      String.ends_with?(path, ".eex") -> true
      File.exists?(path <> ".eex") -> false
      true -> true
    end
  end
end
