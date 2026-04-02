defmodule Familiar.Knowledge.DefaultFiles do
  @moduledoc """
  Installs default MVP workflow and role files during project initialization.

  Workflow files define how the agent approaches common tasks.
  Role files define agent personas for different phases of work.
  """

  @workflows %{
    "feature-planning.md" => """
    # Feature Planning Workflow

    ## Purpose
    Guide the agent through planning a new feature from requirements to specification.

    ## Steps
    1. Understand the feature request
    2. Research existing code for relevant patterns
    3. Draft a specification with acceptance criteria
    4. Identify affected files and modules
    5. Present specification for review
    """,
    "feature-implementation.md" => """
    # Feature Implementation Workflow

    ## Purpose
    Guide the agent through implementing an approved feature specification.

    ## Steps
    1. Review the approved specification
    2. Create or modify files following project conventions
    3. Write tests for new functionality
    4. Validate against acceptance criteria
    5. Report completion with summary of changes
    """,
    "task-fix.md" => """
    # Task Fix Workflow

    ## Purpose
    Guide the agent through fixing a bug or addressing a task.

    ## Steps
    1. Understand the issue and reproduce if possible
    2. Research relevant code and recent changes
    3. Implement the fix following project conventions
    4. Write regression tests
    5. Validate the fix resolves the issue
    """
  }

  @roles %{
    "analyst.md" => """
    # Analyst Role

    ## Purpose
    Research and understand requirements before implementation.

    ## Approach
    - Ask clarifying questions before making assumptions
    - Reference existing knowledge store for context
    - Document findings and recommendations
    - Focus on understanding the "why" behind requirements
    """,
    "coder.md" => """
    # Coder Role

    ## Purpose
    Implement features and fixes following project conventions.

    ## Approach
    - Follow established code patterns and conventions
    - Write tests alongside implementation
    - Keep changes focused and minimal
    - Document decisions in knowledge store
    """,
    "reviewer.md" => """
    # Reviewer Role

    ## Purpose
    Review code changes for correctness, conventions, and quality.

    ## Approach
    - Check for adherence to project conventions
    - Verify test coverage for new functionality
    - Look for potential regressions
    - Suggest improvements without over-engineering
    """
  }

  @doc """
  Install default workflow and role files to the given `.familiar/` directory.

  Does not overwrite existing files.
  """
  @spec install(String.t()) :: :ok
  def install(familiar_dir) do
    install_files(Path.join(familiar_dir, "workflows"), @workflows)
    install_files(Path.join(familiar_dir, "roles"), @roles)
    :ok
  end

  defp install_files(dir, files) do
    File.mkdir_p!(dir)

    Enum.each(files, fn {filename, content} ->
      path = Path.join(dir, filename)

      unless File.exists?(path) do
        File.write!(path, content)
      end
    end)
  end
end
