defmodule PinchflatWeb.Pages.JobTableLiveTest do
  use PinchflatWeb.ConnCase

  import Ecto.Query, warn: false
  import Phoenix.LiveViewTest
  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures

  alias Pinchflat.Pages.JobTableLive
  alias Pinchflat.Downloading.ProgressTracker
  alias Pinchflat.Downloading.MediaDownloadWorker
  alias Pinchflat.FastIndexing.FastIndexingWorker

  describe "initial rendering" do
    test "shows message when no records", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, JobTableLive, session: %{})

      assert html =~ "No running or queued tasks."
      refute html =~ "Subject"
    end

    test "shows records when present", %{conn: conn} do
      {_source, _media_item, _task, _job} = create_media_item_job()
      {:ok, _view, html} = live_isolated(conn, JobTableLive, session: %{})

      assert html =~ "Subject"
    end

    test "includes scheduled and retryable download jobs", %{conn: conn} do
      {_source, scheduled_media_item, _task, _job} = create_media_item_job(:scheduled)
      {_source, retryable_media_item, _task, _job} = create_media_item_job(:retryable)
      {:ok, _view, html} = live_isolated(conn, JobTableLive, session: %{})

      assert html =~ scheduled_media_item.title
      assert html =~ retryable_media_item.title
      assert html =~ "Scheduled"
      assert html =~ "Waiting to retry"
      assert html =~ "Next Eligible At"
    end

    test "includes available jobs as ready", %{conn: conn} do
      {_source, media_item, _task, _job} = create_media_item_job(:available)
      {:ok, _view, html} = live_isolated(conn, JobTableLive, session: %{})

      assert html =~ media_item.title
      assert html =~ "Ready"
      assert html =~ "Now, when a worker is free"
    end

    test "omits completed jobs", %{conn: conn} do
      {_source, _media_item, _task, _job} = create_media_item_job(:completed)
      {:ok, _view, html} = live_isolated(conn, JobTableLive, session: %{})

      assert html =~ "No running or queued tasks."
      refute html =~ "Subject"
    end
  end

  describe "job rendering" do
    test "shows worker name", %{conn: conn} do
      {_source, _media_item, _task, _job} = create_media_item_job()
      {:ok, _view, html} = live_isolated(conn, JobTableLive, session: %{})

      assert html =~ "Downloading Media"
    end

    test "shows live transfer percentage and speed for executing jobs", %{conn: conn} do
      {_source, media_item, _task, _job} = create_media_item_job()

      ProgressTracker.begin_download(media_item.id)

      ProgressTracker.record(
        media_item.id,
        ~s({"status":"downloading","downloaded_bytes":512,"total_bytes":1024,"speed":256,"eta":2})
      )

      {:ok, view, html} = live_isolated(conn, JobTableLive, session: %{})

      assert html =~ "50.0% of 1.0 KiB"
      assert html =~ "256 B/s"
      assert html =~ "ETA 0m 2s"

      ProgressTracker.finish_download(media_item.id)
      assert render_click(view, "refresh_queue") =~ "Preparing download"
    end

    test "shows the media item title", %{conn: conn} do
      {_source, media_item, _task, _job} = create_media_item_job()
      {:ok, _view, html} = live_isolated(conn, JobTableLive, session: %{})

      assert html =~ media_item.title
    end

    test "shows a media item link", %{conn: conn} do
      {_source, media_item, _task, _job} = create_media_item_job()
      {:ok, _view, html} = live_isolated(conn, JobTableLive, session: %{})

      assert html =~ ~p"/sources/#{media_item.source_id}/media/#{media_item}"
    end

    test "shows the source custom name", %{conn: conn} do
      {source, _task, _job} = create_source_job()
      {:ok, _view, html} = live_isolated(conn, JobTableLive, session: %{})

      assert html =~ source.custom_name
    end

    test "shows a source link", %{conn: conn} do
      {source, _task, _job} = create_source_job()
      {:ok, _view, html} = live_isolated(conn, JobTableLive, session: %{})

      assert html =~ ~p"/sources/#{source.id}"
    end

    test "refreshes the task queue on demand", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, JobTableLive, session: %{})
      {_source, media_item, _task, _job} = create_media_item_job(:retryable)

      assert render_click(view, "refresh_queue") =~ media_item.title
    end

    test "listens for job:state change events", %{conn: conn} do
      {_source, _media_item, _task, _job} = create_media_item_job()
      {:ok, _view, _html} = live_isolated(conn, JobTableLive, session: %{})

      PinchflatWeb.Endpoint.broadcast("job:state", "change", nil)

      assert_receive %Phoenix.Socket.Broadcast{topic: "job:state", event: "change", payload: nil}
    end
  end

  defp create_media_item_job(job_state \\ :executing) do
    source = source_fixture()
    media_item = media_item_fixture(source_id: source.id)
    {:ok, task} = MediaDownloadWorker.kickoff_with_task(media_item)

    Oban.Job
    |> where([j], j.id == ^task.job_id)
    |> Repo.update_all(set: [state: to_string(job_state)])

    job = Repo.get!(Oban.Job, task.job_id)

    {source, media_item, task, job}
  end

  defp create_source_job(job_state \\ :executing) do
    source = source_fixture()
    {:ok, task} = FastIndexingWorker.kickoff_with_task(source)

    Oban.Job
    |> where([j], j.id == ^task.job_id)
    |> Repo.update_all(set: [state: to_string(job_state)])

    job = Repo.get!(Oban.Job, task.job_id)

    {source, task, job}
  end
end
