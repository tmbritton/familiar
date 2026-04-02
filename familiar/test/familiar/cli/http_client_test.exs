defmodule Familiar.CLI.HttpClientTest do
  use ExUnit.Case, async: true

  alias Familiar.CLI.HttpClient

  describe "parse_health_response/1" do
    test "parses successful health response" do
      response = %{status: 200, body: %{"status" => "ok", "version" => "0.1.0"}}
      assert {:ok, %{status: "ok", version: "0.1.0"}} = HttpClient.parse_health_response(response)
    end

    test "returns error for non-200 status" do
      response = %{status: 500, body: %{"error" => "internal"}}
      assert {:error, {:daemon_unavailable, %{}}} = HttpClient.parse_health_response(response)
    end

    test "returns error for missing fields" do
      response = %{status: 200, body: %{}}
      assert {:error, {:invalid_config, _}} = HttpClient.parse_health_response(response)
    end
  end

  describe "version_compatible?/2" do
    test "compatible when major versions match" do
      assert HttpClient.version_compatible?("0.1.0", "0.2.0") == true
    end

    test "compatible with identical versions" do
      assert HttpClient.version_compatible?("1.2.3", "1.2.3") == true
    end

    test "incompatible when major versions differ" do
      assert HttpClient.version_compatible?("1.0.0", "2.0.0") == false
    end

    test "compatible with different patch versions" do
      assert HttpClient.version_compatible?("1.0.0", "1.0.5") == true
    end

    test "returns false for unparseable versions" do
      assert HttpClient.version_compatible?("invalid", "1.0.0") == false
    end
  end

  describe "map_error/1" do
    test "maps connection refused to daemon_unavailable" do
      assert {:error, {:daemon_unavailable, %{}}} =
               HttpClient.map_error(%Req.TransportError{reason: :econnrefused})
    end

    test "maps timeout to timeout error" do
      assert {:error, {:timeout, %{}}} =
               HttpClient.map_error(%Req.TransportError{reason: :timeout})
    end

    test "maps other transport errors" do
      assert {:error, {:daemon_unavailable, %{reason: :nxdomain}}} =
               HttpClient.map_error(%Req.TransportError{reason: :nxdomain})
    end
  end
end
