defmodule Familiar.Daemon.ShutdownMarker do
  @moduledoc """
  Clean shutdown marker for crash detection.

  On clean shutdown, a marker file is written. On startup, the absence
  of this marker (when `.familiar/` exists) indicates an unclean shutdown
  and triggers crash recovery.
  """

  alias Familiar.Daemon.Paths

  @doc "Write the shutdown marker (called on clean shutdown)."
  @spec write() :: :ok
  def write do
    Paths.ensure_familiar_dir!()
    File.write!(Paths.shutdown_marker_path(), "")
    :ok
  end

  @doc "Check if the shutdown marker exists."
  @spec exists?() :: boolean()
  def exists? do
    File.exists?(Paths.shutdown_marker_path())
  end

  @doc "Remove the shutdown marker."
  @spec clear() :: :ok
  def clear do
    File.rm(Paths.shutdown_marker_path())
    :ok
  end

  @doc """
  Detect an unclean shutdown.

  Returns `true` if `.familiar/` exists but the shutdown marker does NOT,
  indicating the daemon was killed without a clean shutdown.
  """
  @spec unclean_shutdown?() :: boolean()
  def unclean_shutdown? do
    File.dir?(Paths.familiar_dir()) and not exists?()
  end
end
