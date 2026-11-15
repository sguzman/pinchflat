defmodule Pinchflat.Downloading.ProgressOutput do
  @moduledoc """
  A System.cmd Collectable that consumes yt-dlp progress lines as they arrive.

  Other output is preserved for the existing error handler. Progress lines are
  excluded from the returned output to avoid unbounded per-second log noise.
  """

  defstruct [:media_item_id, output: []]

  @prefix "PINCHFLAT_PROGRESS:"

  def consume(%__MODULE__{} = state, line) when is_binary(line) do
    case line do
      @prefix <> json ->
        Pinchflat.Downloading.ProgressTracker.record(state.media_item_id, json)
        state

      other ->
        %{state | output: [other | state.output]}
    end
  end

  def output(%__MODULE__{output: lines}) do
    lines
    |> Enum.reverse()
    |> Enum.join("\n")
  end
end

defimpl Collectable, for: Pinchflat.Downloading.ProgressOutput do
  def into(original) do
    {original, fn
      state, {:cont, line} -> Pinchflat.Downloading.ProgressOutput.consume(state, line)
      state, :done -> Pinchflat.Downloading.ProgressOutput.output(state)
      _state, :halt -> :ok
    end}
  end
end
