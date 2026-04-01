defmodule FamiliarWeb.DaemonControllerTest do
  use FamiliarWeb.ConnCase

  describe "GET /api/daemon/status" do
    test "returns daemon status in data envelope", %{conn: conn} do
      conn = get(conn, ~p"/api/daemon/status")
      response = json_response(conn, 200)
      assert Map.has_key?(response, "data")
      assert Map.has_key?(response["data"], "status")
    end

    test "returns JSON content type", %{conn: conn} do
      conn = get(conn, ~p"/api/daemon/status")

      assert {"content-type", content_type} =
               List.keyfind(conn.resp_headers, "content-type", 0)

      assert content_type =~ "application/json"
    end
  end

  describe "POST /api/daemon/stop" do
    test "returns error with details when daemon not running", %{conn: conn} do
      # Daemon.Server is disabled in test env
      conn = post(conn, ~p"/api/daemon/stop")
      response = json_response(conn, 409)
      assert response["error"]["type"] == "daemon_unavailable"
      assert Map.has_key?(response["error"], "details")
    end
  end
end
