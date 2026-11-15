defmodule Pinchflat.Downloading.ProgressTrackerTest do
  use ExUnit.Case, async: false

  alias Pinchflat.Downloading.ProgressTracker

  @media_id 99_987_654

  setup do
    ProgressTracker.finish_download(@media_id)
    on_exit(fn -> ProgressTracker.finish_download(@media_id) end)
    :ok
  end

  test "records downloaded bytes, size, rate and ETA for active downloads" do
    :ok = ProgressTracker.begin_download(@media_id)

    :ok =
      ProgressTracker.record(
        @media_id,
        ~s({"status":"downloading","downloaded_bytes":512,"total_bytes":1024,"speed":256,"eta":2})
      )

    assert %{
             status: "downloading",
             downloaded_bytes: 512,
             total_bytes: 1024,
             estimated_total?: false,
             speed_bytes_per_second: 256,
             eta_seconds: 2
           } = ProgressTracker.snapshot()[@media_id]
  end

  test "uses an estimated total when the final size is unavailable" do
    :ok = ProgressTracker.begin_download(@media_id)

    :ok =
      ProgressTracker.record(
        @media_id,
        ~s({"status":"downloading","downloaded_bytes":400,"total_bytes_estimate":2000})
      )

    assert %{total_bytes: 2000, estimated_total?: true} = ProgressTracker.snapshot()[@media_id]
  end

  test "ignores malformed reports and reports from stopped downloads" do
    :ok = ProgressTracker.begin_download(@media_id)
    :ok = ProgressTracker.record(@media_id, "not-json")
    :ok = ProgressTracker.record(@media_id, ~s({"status":"unknown"}))
    assert %{status: "starting"} = ProgressTracker.snapshot()[@media_id]

    :ok = ProgressTracker.finish_download(@media_id)
    :ok = ProgressTracker.record(@media_id, ~s({"status":"downloading","downloaded_bytes":10}))
    refute Map.has_key?(ProgressTracker.snapshot(), @media_id)
  end

  test "starting another attempt clears progress from the previous attempt" do
    :ok = ProgressTracker.begin_download(@media_id)
    :ok = ProgressTracker.record(@media_id, ~s({"status":"downloading","downloaded_bytes":999}))
    assert %{downloaded_bytes: 999} = ProgressTracker.snapshot()[@media_id]

    :ok = ProgressTracker.begin_download(@media_id)
    assert %{status: "starting"} = ProgressTracker.snapshot()[@media_id]

    :ok = ProgressTracker.finish_download(@media_id)
    refute Map.has_key?(ProgressTracker.snapshot(), @media_id)
  end
end
