defmodule FamiliarWeb.HealthControllerTest do
  use FamiliarWeb.ConnCase

  describe "GET /api/health" do
    test "returns ok status and version", %{conn: conn} do
      conn = get(conn, ~p"/api/health")

      assert json_response(conn, 200) == %{
               "status" => "ok",
               "version" => to_string(Application.spec(:familiar, :vsn))
             }
    end

    test "returns 200 status code", %{conn: conn} do
      conn = get(conn, ~p"/api/health")
      assert conn.status == 200
    end

    test "returns JSON content type", %{conn: conn} do
      conn = get(conn, ~p"/api/health")
      assert {"content-type", content_type} = List.keyfind(conn.resp_headers, "content-type", 0)
      assert content_type =~ "application/json"
    end
  end
end
