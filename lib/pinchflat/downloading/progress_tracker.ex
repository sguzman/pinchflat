defmodule Pinchflat.Downloading.ProgressTracker do
  @moduledoc """
  Stores live yt-dlp transfer snapshots for the task queue.

  Progress is transient. Download files and Oban jobs remain the source of
  truth; a process restart simply clears these UI-only snapshots.
  """

  use GenServer

  @name __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @impl true
  def init(state), do: {:ok, state}

  @doc "Returns all currently active download progress snapshots."
  def snapshot, do: GenServer.call(@name, :snapshot)

  @doc "Starts a new transfer, discarding stale progress from an earlier attempt."
  def begin_download(media_item_id), do: GenServer.call(@name, {:begin_download, media_item_id})

  @doc "Clears completed or interrupted transfers."
  def finish_download(media_item_id), do: GenServer.call(@name, {:finish_download, media_item_id})

  @doc "Accepts a JSON progress report from yt-dlp; ignores unexpected output."
  def record(media_item_id, json) when is_binary(json) do
    case Phoenix.json_library().decode(json) do
      {:ok, %{"status" => status} = data} when status in ["downloading", "finished"] ->
        progress = %{
          status: status,
          downloaded_bytes: nonnegative_number(data["downloaded_bytes"]),
          total_bytes: nonnegative_number(data["total_bytes"]) || nonnegative_number(data["total_bytes_estimate"]),
          estimated_total?: is_nil(nonnegative_number(data["total_bytes"])),
          speed_bytes_per_second: nonnegative_number(data["speed"]),
          eta_seconds: nonnegative_number(data["eta"]),
          updated_at: DateTime.utc_now()
        }

        GenServer.cast(@name, {:record, media_item_id, progress})

      _ ->
        :ok
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state, state}

  def handle_call({:begin_download, media_item_id}, _from, state) do
    {:reply, :ok, Map.put(state, media_item_id, %{status: "starting", updated_at: DateTime.utc_now()})}
  end

  def handle_call({:finish_download, media_item_id}, _from, state) do
    {:reply, :ok, Map.delete(state, media_item_id)}
  end

  @impl true
  def handle_cast({:record, media_item_id, progress}, state) do
    # A stopped transfer must never be recreated by a late progress report.
    if Map.has_key?(state, media_item_id) do
      {:noreply, Map.put(state, media_item_id, progress)}
    else
      {:noreply, state}
    end
  end

  defp nonnegative_number(value) when is_number(value) and value >= 0, do: value
  defp nonnegative_number(_), do: nil
end
