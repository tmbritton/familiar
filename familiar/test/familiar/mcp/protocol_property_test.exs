defmodule Familiar.MCP.ProtocolPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Familiar.MCP.Protocol

  # Generators

  defp id_gen do
    one_of([positive_integer(), string(:alphanumeric, min_length: 1, max_length: 20)])
  end

  defp method_gen do
    string(:alphanumeric, min_length: 1, max_length: 30)
  end

  defp simple_value_gen do
    one_of([
      integer(),
      float(),
      string(:printable, max_length: 50),
      boolean(),
      constant(nil)
    ])
  end

  defp params_gen do
    map_of(string(:alphanumeric, min_length: 1, max_length: 10), simple_value_gen(),
      max_length: 5
    )
  end

  # Properties

  property "request encode/decode round-trip" do
    check all(
            id <- id_gen(),
            method <- method_gen(),
            params <- params_gen()
          ) do
      json = Protocol.encode_request(id, method, params)
      assert {:ok, {:request, ^id, ^method, ^params}} = Protocol.decode(json)
    end
  end

  property "response encode/decode round-trip" do
    check all(
            id <- id_gen(),
            result <- simple_value_gen()
          ) do
      json = Protocol.encode_response(id, result)
      assert {:ok, {:response, ^id, ^result}} = Protocol.decode(json)
    end
  end

  property "error encode/decode round-trip without data" do
    check all(
            id <- id_gen(),
            code <- integer(-32_700..-32_600),
            message <- string(:printable, min_length: 1, max_length: 50)
          ) do
      json = Protocol.encode_error(id, code, message)
      assert {:ok, {:error, ^id, ^code, ^message, nil}} = Protocol.decode(json)
    end
  end

  property "error encode/decode round-trip with data" do
    check all(
            id <- id_gen(),
            code <- integer(-32_700..-32_600),
            message <- string(:printable, min_length: 1, max_length: 50),
            data <- params_gen()
          ) do
      json = Protocol.encode_error(id, code, message, data)
      assert {:ok, {:error, ^id, ^code, ^message, ^data}} = Protocol.decode(json)
    end
  end

  property "notification encode/decode round-trip with params" do
    check all(
            method <- method_gen(),
            params <- params_gen()
          ) do
      json = Protocol.encode_notification(method, params)
      assert {:ok, {:notification, ^method, ^params}} = Protocol.decode(json)
    end
  end

  property "notification encode/decode round-trip without params" do
    check all(method <- method_gen()) do
      json = Protocol.encode_notification(method)
      assert {:ok, {:notification, ^method, %{}}} = Protocol.decode(json)
    end
  end

  property "all encoded messages are valid JSON" do
    check all(
            id <- id_gen(),
            method <- method_gen(),
            params <- params_gen()
          ) do
      for json <- [
            Protocol.encode_request(id, method, params),
            Protocol.encode_response(id, %{"ok" => true}),
            Protocol.encode_error(id, -32_600, "err"),
            Protocol.encode_notification(method, params)
          ] do
        assert {:ok, _} = Jason.decode(json)
      end
    end
  end

  property "all encoded messages contain jsonrpc 2.0" do
    check all(
            id <- id_gen(),
            method <- method_gen()
          ) do
      for json <- [
            Protocol.encode_request(id, method),
            Protocol.encode_response(id, nil),
            Protocol.encode_error(id, -32_600, "err"),
            Protocol.encode_notification(method)
          ] do
        assert {:ok, decoded} = Jason.decode(json)
        assert decoded["jsonrpc"] == "2.0"
      end
    end
  end
end
