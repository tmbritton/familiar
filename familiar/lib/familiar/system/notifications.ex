defmodule Familiar.System.Notifications do
  @moduledoc """
  Behaviour for OS-native notifications.

  Implementations auto-detect the platform notification system
  (terminal-notifier on macOS, notify-send on Linux).
  """

  @doc "Send an OS notification with the given title and body."
  @callback notify(title :: String.t(), body :: String.t()) ::
              :ok | {:error, {atom(), map()}}
end
