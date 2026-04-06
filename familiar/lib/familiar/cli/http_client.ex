defmodule Familiar.CLI.HttpClient do
  @moduledoc """
  HTTP client for CLI-to-daemon communication.

  Sends requests to the daemon's local Phoenix API. Reads the daemon port
  from `.familiar/daemon.json` via `Familiar.Daemon.StateFile`.
  """

  alias Familiar.Daemon.StateFile

  @health_path "/api/health"
  @default_timeout 5_000

  @doc """
  Send an HTTP request to the daemon API.

  Options:
  - `:port` — daemon port (auto-discovered from daemon.json if not provided)
  - `:body` — request body (encoded as JSON)
  - `:timeout` — request timeout in ms (default: 5000)
  """
  @spec request(atom(), String.t(), keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def request(method, path, opts \\ []) do
    port = Keyword.get_lazy(opts, :port, fn -> discover_port() end)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case port do
      {:error, _} = error ->
        error

      port when is_integer(port) ->
        url = "http://localhost:#{port}#{path}"
        do_request(method, url, timeout, opts)
    end
  end

  @doc "Health check — GET /api/health."
  @spec health_check(integer()) ::
          {:ok, %{status: String.t(), version: String.t()}} | {:error, {atom(), map()}}
  def health_check(port) do
    url = "http://localhost:#{port}#{@health_path}"

    case Req.get(url,
           connect_options: [timeout: @default_timeout],
           receive_timeout: @default_timeout
         ) do
      {:ok, response} ->
        parse_health_response(response)

      {:error, exception} ->
        map_error(exception)
    end
  end

  @doc false
  @spec parse_health_response(map()) ::
          {:ok, %{status: String.t(), version: String.t()}} | {:error, {atom(), map()}}
  def parse_health_response(%{status: 200, body: %{"status" => status, "version" => version}}) do
    {:ok, %{status: status, version: version}}
  end

  def parse_health_response(%{status: 200, body: _body}) do
    {:error, {:invalid_config, %{reason: :unexpected_health_response}}}
  end

  def parse_health_response(%{status: _status}) do
    {:error, {:daemon_unavailable, %{}}}
  end

  @doc false
  @spec version_compatible?(String.t(), String.t()) :: boolean()
  def version_compatible?(cli_version, daemon_version) do
    with {:ok, cli_parsed} <- Version.parse(cli_version),
         {:ok, daemon_parsed} <- Version.parse(daemon_version) do
      cli_parsed.major == daemon_parsed.major
    else
      _ -> false
    end
  end

  @doc false
  @spec map_error(Exception.t()) :: {:error, {atom(), map()}}
  def map_error(%Req.TransportError{reason: :econnrefused}) do
    {:error, {:daemon_unavailable, %{}}}
  end

  def map_error(%Req.TransportError{reason: :timeout}) do
    {:error, {:timeout, %{}}}
  end

  def map_error(%Req.TransportError{reason: reason}) do
    {:error, {:daemon_unavailable, %{reason: reason}}}
  end

  def map_error(_other) do
    {:error, {:daemon_unavailable, %{}}}
  end

  # -- Private --

  defp discover_port do
    case StateFile.read() do
      {:ok, %{"port" => port}} when is_integer(port) -> port
      {:ok, _} -> {:error, {:daemon_unavailable, %{reason: :invalid_port}}}
      {:error, _} -> {:error, {:daemon_unavailable, %{reason: :no_daemon_json}}}
    end
  end

  defp do_request(method, url, timeout, opts) do
    req_opts = build_req_opts(timeout, opts)

    method
    |> dispatch_req(url, req_opts)
    |> handle_response()
  end

  defp build_req_opts(timeout, opts) do
    base = [connect_options: [timeout: timeout], receive_timeout: timeout]

    case Keyword.get(opts, :body) do
      nil -> base
      body -> Keyword.put(base, :json, body)
    end
  end

  defp dispatch_req(:get, url, opts), do: Req.get(url, opts)
  defp dispatch_req(:post, url, opts), do: Req.post(url, opts)
  defp dispatch_req(:put, url, opts), do: Req.put(url, opts)
  defp dispatch_req(:delete, url, opts), do: Req.delete(url, opts)

  defp handle_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    {:error, {:request_failed, %{status: status, body: body}}}
  end

  defp handle_response({:error, exception}) do
    map_error(exception)
  end
end
