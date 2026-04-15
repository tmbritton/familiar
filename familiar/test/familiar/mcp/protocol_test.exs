defmodule Familiar.MCP.ProtocolTest do
  use ExUnit.Case, async: true

  alias Familiar.MCP.Protocol

  # -- encode_request --

  describe "encode_request/3" do
    test "encodes a request with params" do
      json = Protocol.encode_request(1, "tools/list", %{"cursor" => "abc"})
      decoded = Jason.decode!(json)

      assert decoded["jsonrpc"] == "2.0"
      assert decoded["id"] == 1
      assert decoded["method"] == "tools/list"
      assert decoded["params"] == %{"cursor" => "abc"}
    end

    test "encodes a request with default empty params" do
      json = Protocol.encode_request(42, "initialize")
      decoded = Jason.decode!(json)

      assert decoded["params"] == %{}
    end

    test "accepts string id" do
      json = Protocol.encode_request("req-1", "ping")
      decoded = Jason.decode!(json)

      assert decoded["id"] == "req-1"
    end
  end

  # -- encode_response --

  describe "encode_response/2" do
    test "encodes a success response" do
      json = Protocol.encode_response(1, %{"tools" => []})
      decoded = Jason.decode!(json)

      assert decoded["jsonrpc"] == "2.0"
      assert decoded["id"] == 1
      assert decoded["result"] == %{"tools" => []}
    end

    test "encodes a null result" do
      json = Protocol.encode_response(1, nil)
      decoded = Jason.decode!(json)

      assert decoded["result"] == nil
    end
  end

  # -- encode_error --

  describe "encode_error/4" do
    test "encodes an error without data" do
      json = Protocol.encode_error(1, -32_601, "Method not found")
      decoded = Jason.decode!(json)

      assert decoded["jsonrpc"] == "2.0"
      assert decoded["id"] == 1
      assert decoded["error"]["code"] == -32_601
      assert decoded["error"]["message"] == "Method not found"
      refute Map.has_key?(decoded["error"], "data")
    end

    test "encodes an error with data" do
      json = Protocol.encode_error(1, -32_602, "Invalid params", %{"details" => "missing field"})
      decoded = Jason.decode!(json)

      assert decoded["error"]["data"] == %{"details" => "missing field"}
    end

    test "encodes an error with nil id (parse error)" do
      json = Protocol.encode_error(nil, -32_700, "Parse error")
      decoded = Jason.decode!(json)

      assert decoded["id"] == nil
    end
  end

  # -- encode_notification --

  describe "encode_notification/2" do
    test "encodes a notification without params" do
      json = Protocol.encode_notification("notifications/initialized")
      decoded = Jason.decode!(json)

      assert decoded["jsonrpc"] == "2.0"
      assert decoded["method"] == "notifications/initialized"
      refute Map.has_key?(decoded, "id")
      refute Map.has_key?(decoded, "params")
    end

    test "encodes a notification with params" do
      json =
        Protocol.encode_notification("notifications/resources/updated", %{
          "uri" => "file:///a.txt"
        })

      decoded = Jason.decode!(json)

      assert decoded["params"] == %{"uri" => "file:///a.txt"}
      refute Map.has_key?(decoded, "id")
    end
  end

  # -- decode --

  describe "decode/1 — requests" do
    test "decodes a request" do
      json = ~s({"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"cursor":"x"}})
      assert {:ok, {:request, 1, "tools/list", %{"cursor" => "x"}}} = Protocol.decode(json)
    end

    test "decodes a request without params" do
      json = ~s({"jsonrpc":"2.0","id":1,"method":"ping"})
      assert {:ok, {:request, 1, "ping", %{}}} = Protocol.decode(json)
    end

    test "decodes a request with string id" do
      json = ~s({"jsonrpc":"2.0","id":"req-7","method":"test"})
      assert {:ok, {:request, "req-7", "test", %{}}} = Protocol.decode(json)
    end
  end

  describe "decode/1 — responses" do
    test "decodes a success response" do
      json = ~s({"jsonrpc":"2.0","id":1,"result":{"tools":[]}})
      assert {:ok, {:response, 1, %{"tools" => []}}} = Protocol.decode(json)
    end

    test "decodes a response with null result" do
      json = ~s({"jsonrpc":"2.0","id":1,"result":null})
      assert {:ok, {:response, 1, nil}} = Protocol.decode(json)
    end
  end

  describe "decode/1 — errors" do
    test "decodes an error response" do
      json = ~s({"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}})
      assert {:ok, {:error, 1, -32_601, "Method not found", nil}} = Protocol.decode(json)
    end

    test "decodes an error response with data" do
      json =
        ~s({"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"Bad params","data":{"field":"x"}}})

      assert {:ok, {:error, 1, -32_602, "Bad params", %{"field" => "x"}}} = Protocol.decode(json)
    end

    test "decodes an error response with nil id" do
      json = ~s({"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}})
      assert {:ok, {:error, nil, -32_700, "Parse error", nil}} = Protocol.decode(json)
    end
  end

  describe "decode/1 — notifications" do
    test "decodes a notification" do
      json = ~s({"jsonrpc":"2.0","method":"notifications/initialized"})
      assert {:ok, {:notification, "notifications/initialized", %{}}} = Protocol.decode(json)
    end

    test "decodes a notification with params" do
      json =
        ~s({"jsonrpc":"2.0","method":"notifications/tools/list_changed","params":{"reason":"update"}})

      assert {:ok, {:notification, "notifications/tools/list_changed", %{"reason" => "update"}}} =
               Protocol.decode(json)
    end
  end

  describe "decode/1 — edge cases" do
    test "returns parse_error for invalid JSON" do
      assert {:error, {:parse_error, _reason}} = Protocol.decode("not json")
    end

    test "returns invalid_request for JSON array (batch not supported)" do
      assert {:error, {:invalid_request, "batch requests are not supported"}} =
               Protocol.decode(~s([{"jsonrpc":"2.0","id":1,"method":"test"}]))
    end

    test "returns invalid_request for non-object, non-array JSON" do
      assert {:error, {:invalid_request, "message must be a JSON object"}} =
               Protocol.decode("42")
    end

    test "returns invalid_request for missing jsonrpc field" do
      json = ~s({"id":1,"method":"test"})
      assert {:error, {:invalid_request, "missing jsonrpc field"}} = Protocol.decode(json)
    end

    test "returns invalid_request for wrong jsonrpc version" do
      json = ~s({"jsonrpc":"1.0","id":1,"method":"test"})

      assert {:error, {:invalid_request, "unsupported jsonrpc version:" <> _}} =
               Protocol.decode(json)
    end

    test "returns invalid_request for empty object" do
      assert {:error, {:invalid_request, "missing jsonrpc field"}} = Protocol.decode("{}")
    end

    test "returns invalid_request for object with only jsonrpc" do
      json = ~s({"jsonrpc":"2.0"})
      assert {:error, {:invalid_request, "missing required fields"}} = Protocol.decode(json)
    end

    test "extra fields are ignored" do
      json = ~s({"jsonrpc":"2.0","id":1,"method":"test","extra":"ignored"})
      assert {:ok, {:request, 1, "test", %{}}} = Protocol.decode(json)
    end

    test "non-string method returns invalid_request" do
      json = ~s({"jsonrpc":"2.0","id":1,"method":123})
      assert {:error, {:invalid_request, "missing required fields"}} = Protocol.decode(json)
    end

    test "rejects message with both result and error" do
      json = ~s({"jsonrpc":"2.0","id":1,"result":{},"error":{"code":-32600,"message":"bad"}})

      assert {:error, {:invalid_request, "message contains both result and error"}} =
               Protocol.decode(json)
    end

    test "rejects response without id" do
      json = ~s({"jsonrpc":"2.0","result":42})
      assert {:error, {:invalid_request, "response missing id"}} = Protocol.decode(json)
    end

    test "params: null is decoded as empty map" do
      json = ~s({"jsonrpc":"2.0","id":1,"method":"test","params":null})
      assert {:ok, {:request, 1, "test", nil}} = Protocol.decode(json)
    end
  end

  # -- encode/decode round-trip --

  describe "encode/decode round-trip" do
    test "request round-trips" do
      json = Protocol.encode_request(42, "tools/call", %{"name" => "test"})
      assert {:ok, {:request, 42, "tools/call", %{"name" => "test"}}} = Protocol.decode(json)
    end

    test "response round-trips" do
      json = Protocol.encode_response(7, %{"data" => [1, 2, 3]})
      assert {:ok, {:response, 7, %{"data" => [1, 2, 3]}}} = Protocol.decode(json)
    end

    test "error round-trips" do
      json = Protocol.encode_error(3, -32_601, "Not found", %{"method" => "x"})
      assert {:ok, {:error, 3, -32_601, "Not found", %{"method" => "x"}}} = Protocol.decode(json)
    end

    test "error without data round-trips" do
      json = Protocol.encode_error(3, -32_601, "Not found")
      assert {:ok, {:error, 3, -32_601, "Not found", nil}} = Protocol.decode(json)
    end

    test "notification round-trips" do
      json = Protocol.encode_notification("test/event", %{"key" => "val"})
      assert {:ok, {:notification, "test/event", %{"key" => "val"}}} = Protocol.decode(json)
    end

    test "notification without params round-trips" do
      json = Protocol.encode_notification("test/event")
      assert {:ok, {:notification, "test/event", %{}}} = Protocol.decode(json)
    end
  end

  # -- error_code --

  describe "error_code/1" do
    test "parse_error" do
      assert Protocol.error_code(:parse_error) == -32_700
    end

    test "invalid_request" do
      assert Protocol.error_code(:invalid_request) == -32_600
    end

    test "method_not_found" do
      assert Protocol.error_code(:method_not_found) == -32_601
    end

    test "invalid_params" do
      assert Protocol.error_code(:invalid_params) == -32_602
    end

    test "internal_error" do
      assert Protocol.error_code(:internal_error) == -32_603
    end
  end
end
