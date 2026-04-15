defmodule Familiar.MCP.Protocol do
  @moduledoc """
  JSON-RPC 2.0 codec for the Model Context Protocol.

  Encodes and decodes MCP messages with no coupling to transport details.
  All functions are pure — no IO, no process state.

  ## Message Types

    * **Request** — has `id`, expects a response
    * **Response** — success result for a request
    * **Error** — error result for a request
    * **Notification** — no `id`, no response expected
  """

  @jsonrpc_version "2.0"

  # Standard JSON-RPC 2.0 error codes
  @parse_error -32_700
  @invalid_request -32_600
  @method_not_found -32_601
  @invalid_params -32_602
  @internal_error -32_603

  @type id :: integer() | String.t()
  @type params :: map() | nil
  @type error_code_name ::
          :parse_error | :invalid_request | :method_not_found | :invalid_params | :internal_error

  @type decoded_message ::
          {:request, id(), String.t(), map()}
          | {:response, id(), term()}
          | {:error, id() | nil, integer(), String.t(), term()}
          | {:notification, String.t(), map()}

  # -- Encode --

  @doc "Encodes a JSON-RPC 2.0 request."
  @spec encode_request(id(), String.t(), map()) :: String.t()
  def encode_request(id, method, params \\ %{}) do
    %{"jsonrpc" => @jsonrpc_version, "id" => id, "method" => method, "params" => params}
    |> Jason.encode!()
  end

  @doc "Encodes a JSON-RPC 2.0 success response."
  @spec encode_response(id(), term()) :: String.t()
  def encode_response(id, result) do
    %{"jsonrpc" => @jsonrpc_version, "id" => id, "result" => result}
    |> Jason.encode!()
  end

  @doc "Encodes a JSON-RPC 2.0 error response."
  @spec encode_error(id() | nil, integer(), String.t(), term()) :: String.t()
  def encode_error(id, code, message, data \\ nil) do
    error = %{"code" => code, "message" => message}
    error = if data != nil, do: Map.put(error, "data", data), else: error

    %{"jsonrpc" => @jsonrpc_version, "id" => id, "error" => error}
    |> Jason.encode!()
  end

  @doc "Encodes a JSON-RPC 2.0 notification (no id, no response expected)."
  @spec encode_notification(String.t(), params()) :: String.t()
  def encode_notification(method, params \\ nil) do
    msg = %{"jsonrpc" => @jsonrpc_version, "method" => method}
    msg = if params != nil, do: Map.put(msg, "params", params), else: msg
    Jason.encode!(msg)
  end

  # -- Decode --

  @doc "Decodes a JSON-RPC 2.0 message from a JSON string."
  @spec decode(String.t()) ::
          {:ok, decoded_message()} | {:error, {:parse_error | :invalid_request, String.t()}}
  def decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, decoded} when is_map(decoded) ->
        classify(decoded)

      {:ok, decoded} when is_list(decoded) ->
        {:error, {:invalid_request, "batch requests are not supported"}}

      {:ok, _} ->
        {:error, {:invalid_request, "message must be a JSON object"}}

      {:error, %Jason.DecodeError{} = err} ->
        {:error, {:parse_error, Exception.message(err)}}
    end
  end

  # -- Error Codes --

  @doc "Maps an error code atom to its integer value."
  @spec error_code(error_code_name()) :: -32_700 | -32_600 | -32_601 | -32_602 | -32_603
  def error_code(:parse_error), do: @parse_error
  def error_code(:invalid_request), do: @invalid_request
  def error_code(:method_not_found), do: @method_not_found
  def error_code(:invalid_params), do: @invalid_params
  def error_code(:internal_error), do: @internal_error

  @doc "Returns the standard JSON-RPC version string."
  @spec jsonrpc_version() :: String.t()
  def jsonrpc_version, do: @jsonrpc_version

  # -- Private: Message Classification --

  defp classify(%{"jsonrpc" => @jsonrpc_version} = msg) do
    has_result = Map.has_key?(msg, "result")
    has_error = match?(%{"error" => %{"code" => _, "message" => _}}, msg)
    has_method = is_binary(msg["method"])

    cond do
      has_result and has_error ->
        {:error, {:invalid_request, "message contains both result and error"}}

      has_error ->
        classify_error(msg)

      has_result ->
        classify_response(msg)

      has_method ->
        classify_request_or_notification(msg)

      true ->
        {:error, {:invalid_request, "missing required fields"}}
    end
  end

  defp classify(%{"jsonrpc" => version}) when version != @jsonrpc_version do
    {:error, {:invalid_request, "unsupported jsonrpc version: #{inspect(version)}"}}
  end

  defp classify(_msg) do
    {:error, {:invalid_request, "missing jsonrpc field"}}
  end

  defp classify_error(msg) do
    error = msg["error"]
    {:ok, {:error, msg["id"], error["code"], error["message"], error["data"]}}
  end

  defp classify_response(msg) do
    if Map.has_key?(msg, "id") do
      {:ok, {:response, msg["id"], msg["result"]}}
    else
      {:error, {:invalid_request, "response missing id"}}
    end
  end

  defp classify_request_or_notification(msg) do
    params = if Map.has_key?(msg, "params"), do: msg["params"], else: %{}

    if Map.has_key?(msg, "id") do
      {:ok, {:request, msg["id"], msg["method"], params}}
    else
      {:ok, {:notification, msg["method"], params}}
    end
  end
end
