defmodule Pinchflat.Pages.JobTableLive do
  use PinchflatWeb, :live_view
  use Pinchflat.Tasks.TasksQuery

  alias Pinchflat.Repo
  alias Pinchflat.Tasks.Task
  alias PinchflatWeb.CustomComponents.TextComponents

  def render(%{tasks: []} = assigns) do
    ~H"""
    <div class="mb-4 flex items-center">
      <.icon_button icon_name="hero-arrow-path" class="h-10 w-10" phx-click="refresh_queue" tooltip="Refresh" />
      <p class="ml-2">No running or queued tasks. Pending videos may not have a scheduled job.</p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-4 flex items-center">
        <.icon_button icon_name="hero-arrow-path" class="h-10 w-10" phx-click="refresh_queue" tooltip="Refresh" />
        <p class="ml-2">
          Showing {length(@tasks)} running or queued tasks (up to 100). Scheduled times are eligibility times, not guaranteed start times.
        </p>
      </div>
      <div class="max-w-full overflow-x-auto">
        <.table rows={@tasks} table_class="text-white">
          <:col :let={task} label="Task">
            {worker_to_task_name(task.job.worker)}
          </:col>
          <:col :let={task} label="Subject" class="truncate max-w-xs">
            <.subtle_link href={task_to_link(task)}>
              {task_to_record_name(task)}
            </.subtle_link>
          </:col>
          <:col :let={task} label="Status">
            {format_job_state(task.job.state)}
          </:col>
          <:col :let={task} label="Attempt No.">
            {task.job.attempt}
          </:col>
          <:col :let={task} label="Next Eligible At">
            {format_next_eligible_at(task.job)}
          </:col>
          <:col :let={task} label="Last Started">
            {format_datetime(task.job.attempted_at)}
          </:col>
        </.table>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    PinchflatWeb.Endpoint.subscribe("job:state")

    {:ok, assign(socket, tasks: get_tasks())}
  end

  def handle_info(%{topic: "job:state", event: "change"}, socket) do
    {:noreply, assign(socket, tasks: get_tasks())}
  end

  def handle_event("refresh_queue", _params, socket) do
    {:noreply, assign(socket, tasks: get_tasks())}
  end

  defp get_tasks do
    TasksQuery.new()
    |> TasksQuery.join_job()
    |> where(^TasksQuery.in_state(["executing", "available", "scheduled", "retryable"]))
    |> where(^TasksQuery.has_tag("show_in_dashboard"))
    |> order_by([t, j], asc: j.scheduled_at)
    |> limit(100)
    |> Repo.all()
    |> Repo.preload([:media_item, :source])
  end

  defp worker_to_task_name(worker) do
    final_module_part =
      worker
      |> String.split(".")
      |> Enum.at(-1)

    map_worker_to_task_name(final_module_part)
  end

  defp map_worker_to_task_name("FastIndexingWorker"), do: "Fast Indexing Source"
  defp map_worker_to_task_name("MediaDownloadWorker"), do: "Downloading Media"
  defp map_worker_to_task_name("MediaCollectionIndexingWorker"), do: "Indexing Source"
  defp map_worker_to_task_name("MediaQualityUpgradeWorker"), do: "Upgrading Media Quality"
  defp map_worker_to_task_name("SourceMetadataStorageWorker"), do: "Fetching Source Metadata"
  defp map_worker_to_task_name(other), do: other <> " (Report to Devs)"

  defp task_to_record_name(%Task{} = task) do
    case task do
      %Task{source: source} when source != nil -> source.custom_name
      %Task{media_item: mi} when mi != nil -> mi.title
      _ -> "Unknown Record"
    end
  end

  defp task_to_link(%Task{} = task) do
    case task do
      %Task{source: source} when source != nil -> ~p"/sources/#{source.id}"
      %Task{media_item: mi} when mi != nil -> ~p"/sources/#{mi.source_id}/media/#{mi}"
      _ -> "#"
    end
  end

  defp format_job_state("executing"), do: "Running"
  defp format_job_state("available"), do: "Ready"
  defp format_job_state("scheduled"), do: "Scheduled"
  defp format_job_state("retryable"), do: "Waiting to retry"
  defp format_job_state(state), do: state

  defp format_next_eligible_at(%Oban.Job{state: "executing"}), do: "In progress"
  defp format_next_eligible_at(%Oban.Job{state: "available"}), do: "Now, when a worker is free"
  defp format_next_eligible_at(%Oban.Job{scheduled_at: datetime}), do: format_datetime(datetime)

  defp format_datetime(nil), do: ""

  defp format_datetime(datetime) do
    TextComponents.datetime_in_zone(%{datetime: datetime, format: "%Y-%m-%d %H:%M"})
  end
end
