defmodule Pinchflat.Downloading.ProgressOutputTest do
  use ExUnit.Case, async: false

  alias Pinchflat.Downloading.ProgressOutput
  alias Pinchflat.Downloading.ProgressTracker

  @media_id 99_987_655

  setup do
    ProgressTracker.begin_download(@media_id)
    on_exit(fn -> ProgressTracker.finish_download(@media_id) end)
    :ok
  end

  test "streams progress into the tracker and retains non-progress diagnostics" do
    output =
      Enum.into(
        [
          "warning: slow connection",
          ~s(PINCHFLAT_PROGRESS:{"status":"downloading","downloaded_bytes":1024,"speed":512}),
          "ERROR: connection closed"
        ],
        %ProgressOutput{media_item_id: @media_id}
      )

    assert output == "warning: slow connection\nERROR: connection closed"
    assert %{downloaded_bytes: 1024, speed_bytes_per_second: 512} =
             ProgressTracker.snapshot()[@media_id]
  end

  test "keeps malformed progress lines out of diagnostics" do
    output = Enum.into(["PINCHFLAT_PROGRESS:bad-json", "warning"], %ProgressOutput{media_item_id: @media_id})

    assert output == "warning"
    assert %{status: "starting"} = ProgressTracker.snapshot()[@media_id]
  end
end
