defmodule Familiar.CLI.ValidateTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.CLI.Main
  alias Familiar.CLI.Output
  alias Familiar.Daemon.Paths

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    Paths.ensure_familiar_dir!()
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  defp deps(overrides \\ []) do
    base = %{
      ensure_running_fn: fn _opts -> {:ok, 4000} end,
      health_fn: fn _port -> {:ok, %{status: "ok", version: "0.1.0"}} end,
      daemon_status_fn: fn _opts -> {:stopped, %{}} end,
      stop_daemon_fn: fn _opts -> {:error, {:daemon_unavailable, %{}}} end
    }

    Map.merge(base, Map.new(overrides))
  end

  defp mock_validation(roles \\ [], skills \\ [], workflows \\ []) do
    passed = Enum.count(roles ++ skills ++ workflows, &(&1.status == :pass))
    warnings = Enum.count(roles ++ skills ++ workflows, &(&1.status == :warn))
    errors = Enum.count(roles ++ skills ++ workflows, &(&1.status == :error))

    fn _args, _opts ->
      {:ok,
       %{
         validation: %{
           roles: roles,
           skills: skills,
           workflows: workflows,
           summary: %{passed: passed, warnings: warnings, errors: errors}
         }
       }}
    end
  end

  # == fam validate ==

  describe "fam validate" do
    test "validates all and returns summary" do
      roles = [%{name: "analyst", type: :role, status: :pass}]
      skills = [%{name: "implement", type: :skill, status: :pass}]
      workflows = [%{name: "feature-planning", type: :workflow, status: :pass}]

      d = deps(validate_fn: mock_validation(roles, skills, workflows))

      assert {:ok, %{validation: v}} = Main.run({"validate", [], %{}}, d)
      assert v.summary.passed == 3
      assert v.summary.warnings == 0
      assert v.summary.errors == 0
    end

    test "reports errors and warnings" do
      roles = [
        %{name: "good", type: :role, status: :pass},
        %{name: "bad", type: :role, status: :error, message: "missing skill 'x'"}
      ]

      skills = [
        %{name: "custom", type: :skill, status: :warn, message: "unknown tool 'foo'"}
      ]

      d = deps(validate_fn: mock_validation(roles, skills))

      assert {:ok, %{validation: v}} = Main.run({"validate", [], %{}}, d)
      assert v.summary.passed == 1
      assert v.summary.warnings == 1
      assert v.summary.errors == 1
    end
  end

  describe "fam validate <type>" do
    test "validate roles passes args through" do
      test_pid = self()

      d =
        deps(
          validate_fn: fn args, _opts ->
            send(test_pid, {:validate_called, args})

            {:ok,
             %{
               validation: %{
                 roles: [],
                 skills: [],
                 workflows: [],
                 summary: %{passed: 0, warnings: 0, errors: 0}
               }
             }}
          end
        )

      Main.run({"validate", ["roles"], %{}}, d)
      assert_receive {:validate_called, ["roles"]}
    end

    test "validate skills passes args through" do
      test_pid = self()

      d =
        deps(
          validate_fn: fn args, _opts ->
            send(test_pid, {:validate_called, args})

            {:ok,
             %{
               validation: %{
                 roles: [],
                 skills: [],
                 workflows: [],
                 summary: %{passed: 0, warnings: 0, errors: 0}
               }
             }}
          end
        )

      Main.run({"validate", ["skills"], %{}}, d)
      assert_receive {:validate_called, ["skills"]}
    end

    test "validate workflows passes args through" do
      test_pid = self()

      d =
        deps(
          validate_fn: fn args, _opts ->
            send(test_pid, {:validate_called, args})

            {:ok,
             %{
               validation: %{
                 roles: [],
                 skills: [],
                 workflows: [],
                 summary: %{passed: 0, warnings: 0, errors: 0}
               }
             }}
          end
        )

      Main.run({"validate", ["workflows"], %{}}, d)
      assert_receive {:validate_called, ["workflows"]}
    end
  end

  # == Output formatting ==

  describe "output formatting" do
    test "quiet mode shows summary" do
      result =
        {:ok,
         %{
           validation: %{
             roles: [],
             skills: [],
             workflows: [],
             summary: %{passed: 5, warnings: 1, errors: 0}
           }
         }}

      assert Output.format(result, :quiet) == "validate:5ok:1warn:0err"
    end

    test "json mode returns full validation result" do
      result =
        {:ok,
         %{
           validation: %{
             roles: [%{name: "analyst", status: :pass}],
             skills: [],
             workflows: [],
             summary: %{passed: 1, warnings: 0, errors: 0}
           }
         }}

      json = Output.format(result, :json)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["data"]["validation"]["summary"]["passed"] == 1
    end
  end
end
