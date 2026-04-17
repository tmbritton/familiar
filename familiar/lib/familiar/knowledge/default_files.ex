defmodule Familiar.Knowledge.DefaultFiles do
  @moduledoc """
  Installs default MVP workflow, role, and skill files during project initialization.

  Default files are stored as markdown in `priv/defaults/` and compiled into
  the module at build time. On install, they are written to the project's
  `.familiar/` directory. Existing files are never overwritten, preserving
  user customizations.
  """

  @subdirs ~w(workflows roles skills)

  # Read all default files from priv/defaults/ at compile time.
  # This ensures the escript includes the content without needing
  # runtime access to the priv directory.
  @defaults (for subdir <- @subdirs,
                 filename <-
                   File.ls!(Path.join([:code.priv_dir(:familiar), "defaults", subdir])),
                 String.ends_with?(filename, ".md") do
               path = Path.join([:code.priv_dir(:familiar), "defaults", subdir, filename])
               @external_resource path
               {subdir, filename, File.read!(path)}
             end)

  @doc """
  Install default workflow, role, and skill files to the given `.familiar/` directory.

  Does not overwrite existing files.
  """
  @spec install(String.t()) :: :ok
  def install(familiar_dir) do
    for subdir <- @subdirs do
      File.mkdir_p!(Path.join(familiar_dir, subdir))
    end

    for {subdir, filename, content} <- @defaults do
      dst = Path.join([familiar_dir, subdir, filename])

      unless File.exists?(dst) do
        File.write!(dst, content)
      end
    end

    :ok
  end

  @doc false
  def priv_defaults_path do
    Path.join(:code.priv_dir(:familiar), "defaults")
  end
end
