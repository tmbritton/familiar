defmodule FamiliarWeb.PlanningChannelTest do
  use FamiliarWeb.ChannelCase, async: false

  setup do
    {:ok, _, socket} =
      FamiliarWeb.UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(FamiliarWeb.PlanningChannel, "planning:lobby")

    %{socket: socket}
  end

  describe "join" do
    test "joins planning:lobby successfully", %{socket: socket} do
      assert socket.joined
    end
  end

  describe "stubbed commands" do
    test "start_plan returns not_implemented", %{socket: socket} do
      ref = push(socket, "start_plan", %{"description" => "add auth"})
      assert_reply ref, :error, %{reason: "not_implemented"}
    end

    test "respond returns not_implemented", %{socket: socket} do
      ref = push(socket, "respond", %{"session_id" => 1, "message" => "test"})
      assert_reply ref, :error, %{reason: "not_implemented"}
    end

    test "resume with session_id returns not_implemented", %{socket: socket} do
      ref = push(socket, "resume", %{"session_id" => 1})
      assert_reply ref, :error, %{reason: "not_implemented"}
    end

    test "resume without session_id returns not_implemented", %{socket: socket} do
      ref = push(socket, "resume", %{})
      assert_reply ref, :error, %{reason: "not_implemented"}
    end

    test "generate_spec returns not_implemented", %{socket: socket} do
      ref = push(socket, "generate_spec", %{"session_id" => 1})
      assert_reply ref, :error, %{reason: "not_implemented"}
    end
  end
end
