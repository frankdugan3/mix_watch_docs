defmodule MixWatchDocs.Watcher do
  @moduledoc false
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    debounce_ms = opts[:debounce_ms] || 500
    {:ok, pid} = FileSystem.start_link(dirs: opts[:dirs])
    FileSystem.subscribe(pid)
    {:ok, %{fs_pid: pid, debounce_ms: debounce_ms, timer: nil, cooldown: false}}
  end

  @impl true
  def handle_info({:file_event, _, {_, _}}, %{cooldown: true} = state) do
    {:noreply, state}
  end

  def handle_info({:file_event, _, {path, _}}, state) do
    if source_file?(path) do
      if state.timer, do: Process.cancel_timer(state.timer)
      timer = Process.send_after(self(), :rebuild, state.debounce_ms)
      {:noreply, %{state | timer: timer}}
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
    Process.send_after(self(), :cooldown_done, state.debounce_ms)
    {:noreply, %{state | timer: nil, cooldown: true}}
  end

  def handle_info(:cooldown_done, state) do
    {:noreply, %{state | cooldown: false}}
  end

  defp source_file?(path) when is_binary(path) do
    cond do
      String.ends_with?(path, ".eex") -> true
      File.exists?(path <> ".eex") -> false
      true -> true
    end
  end
end
