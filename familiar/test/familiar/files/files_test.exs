defmodule Familiar.FilesTest do
  use Familiar.DataCase, async: false
  use ExUnitProperties

  import Mox

  alias Familiar.Files
  alias Familiar.Files.Transaction

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()
    :ok
  end

  # == Transaction Schema ==

  describe "Transaction changeset" do
    test "valid changeset with all required fields" do
      attrs = %{task_id: "t1", file_path: "/a.ex", content_hash: "abc123", status: "pending"}
      changeset = Transaction.changeset(%Transaction{}, attrs)
      assert changeset.valid?
    end

    test "requires task_id, file_path, content_hash" do
      changeset = Transaction.changeset(%Transaction{}, %{})
      errors = errors_on(changeset)
      assert errors[:task_id]
      assert errors[:file_path]
      assert errors[:content_hash]
    end

    test "validates status inclusion" do
      attrs = %{task_id: "t1", file_path: "/a.ex", content_hash: "abc", status: "bogus"}
      changeset = Transaction.changeset(%Transaction{}, attrs)
      refute changeset.valid?
      assert errors_on(changeset)[:status]
    end

    test "allows nil original_content_hash for new files" do
      attrs = %{
        task_id: "t1",
        file_path: "/new.ex",
        content_hash: "abc",
        status: "pending",
        original_content_hash: nil
      }

      changeset = Transaction.changeset(%Transaction{}, attrs)
      assert changeset.valid?
    end

    test "all valid statuses are accepted" do
      for status <- ~w(pending completed rolled_back skipped conflict) do
        attrs = %{task_id: "t1", file_path: "/a.ex", content_hash: "abc", status: status}
        changeset = Transaction.changeset(%Transaction{}, attrs)
        assert changeset.valid?, "Expected status #{status} to be valid"
      end
    end
  end

  describe "Transaction.content_hash/1" do
    test "returns lowercase hex SHA-256" do
      hash = Transaction.content_hash("hello world")
      assert is_binary(hash)
      assert String.length(hash) == 64
      assert hash == String.downcase(hash)
      assert hash == Transaction.content_hash("hello world")
    end

    test "different content produces different hashes" do
      refute Transaction.content_hash("a") == Transaction.content_hash("b")
    end
  end

  # == Files.write/3 ==

  describe "Files.write/3" do
    test "golden path — logs intent, writes file, logs completion" do
      content = "defmodule Foo do\nend"

      Familiar.System.FileSystemMock
      |> stub(:read, fn "/project/lib/foo.ex" -> {:error, {:file_error, %{reason: :enoent}}} end)
      |> expect(:write, fn "/project/lib/foo.ex", ^content -> :ok end)

      assert {:ok, txn} = Files.write("/project/lib/foo.ex", content, "task_1")
      assert txn.status == "completed"
      assert txn.task_id == "task_1"
      assert txn.file_path == "/project/lib/foo.ex"
      assert txn.content_hash == Transaction.content_hash(content)
      assert txn.original_content_hash == nil
    end

    test "writes to existing file — stores original hash" do
      original = "old content"
      new_content = "new content"
      original_hash = Transaction.content_hash(original)

      Familiar.System.FileSystemMock
      |> stub(:read, fn "/project/lib/foo.ex" -> {:ok, original} end)
      |> expect(:write, fn "/project/lib/foo.ex", ^new_content -> :ok end)

      assert {:ok, txn} = Files.write("/project/lib/foo.ex", new_content, "task_1")
      assert txn.status == "completed"
      assert txn.original_content_hash == original_hash
    end

    test "returns error when file write fails" do
      Familiar.System.FileSystemMock
      |> stub(:read, fn _path -> {:error, {:file_error, %{reason: :enoent}}} end)
      |> expect(:write, fn _path, _content ->
        {:error, {:file_error, %{reason: :eacces}}}
      end)

      assert {:error, {:file_operation_failed, _}} =
               Files.write("/readonly/foo.ex", "content", "task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "rolled_back"
    end

    test "same task can re-write file after completion" do
      Familiar.System.FileSystemMock
      |> stub(:read, fn _p -> {:error, {:file_error, %{reason: :enoent}}} end)
      |> stub(:write, fn _p, _c -> :ok end)

      assert {:ok, _} = Files.write("/project/a.ex", "content", "task_1")
      assert {:ok, _} = Files.write("/project/a.ex", "v2", "task_1")

      # Only the latest transaction remains
      txns = Repo.all(from(t in Transaction, where: t.file_path == "/project/a.ex"))
      assert length(txns) == 1
      assert hd(txns).content_hash == Transaction.content_hash("v2")
    end
  end

  # == Files.delete/2 ==

  describe "Files.delete/2" do
    test "golden path — reads original, deletes file, logs completion" do
      original = "original content"

      Familiar.System.FileSystemMock
      |> stub(:read, fn "/project/old.ex" -> {:ok, original} end)
      |> expect(:delete, fn "/project/old.ex" -> :ok end)

      assert {:ok, txn} = Files.delete("/project/old.ex", "task_1")
      assert txn.status == "completed"
      assert txn.original_content_hash == Transaction.content_hash(original)
      assert txn.content_hash == "DELETE"
    end

    test "returns error when delete fails" do
      Familiar.System.FileSystemMock
      |> stub(:read, fn _p -> {:ok, "content"} end)
      |> expect(:delete, fn _p -> {:error, {:file_error, %{reason: :eacces}}} end)

      assert {:error, {:file_operation_failed, _}} =
               Files.delete("/readonly/foo.ex", "task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "rolled_back"
    end
  end

  # == Files.rollback_task/1 ==

  describe "Files.rollback_task/1" do
    test "rolls back pending write of new file — deletes it" do
      content = "new file content"
      hash = Transaction.content_hash(content)

      {:ok, _txn} =
        Repo.insert(
          Transaction.changeset(%Transaction{}, %{
            task_id: "task_1",
            file_path: "/project/new.ex",
            content_hash: hash,
            status: "pending"
          })
        )

      # File matches what we wrote, no original → delete
      Familiar.System.FileSystemMock
      |> expect(:read, fn "/project/new.ex" -> {:ok, content} end)
      |> expect(:delete, fn "/project/new.ex" -> :ok end)

      assert :ok = Files.rollback_task("task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "rolled_back"
    end

    test "rolls back overwrite of tracked file via git restore" do
      content = "agent's overwrite"
      hash = Transaction.content_hash(content)
      orig_hash = Transaction.content_hash("original")

      {:ok, _txn} =
        Repo.insert(
          Transaction.changeset(%Transaction{}, %{
            task_id: "task_1",
            file_path: "/project/existing.ex",
            content_hash: hash,
            original_content_hash: orig_hash,
            status: "pending"
          })
        )

      # File matches our write
      Familiar.System.FileSystemMock
      |> expect(:read, fn "/project/existing.ex" -> {:ok, content} end)

      # Git: file is tracked → restore from HEAD
      Familiar.System.ShellMock
      |> expect(:cmd, fn "git", ["ls-files", "--error-unmatch", "/project/existing.ex"], [] ->
        {:ok, %{output: "/project/existing.ex", exit_code: 0}}
      end)
      |> expect(:cmd, fn "git", ["checkout", "HEAD", "--", "/project/existing.ex"], [] ->
        {:ok, %{output: "", exit_code: 0}}
      end)

      assert :ok = Files.rollback_task("task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "rolled_back"
    end

    test "skips overwrite rollback when file is untracked" do
      content = "agent's overwrite"
      hash = Transaction.content_hash(content)
      orig_hash = Transaction.content_hash("original")

      {:ok, _txn} =
        Repo.insert(
          Transaction.changeset(%Transaction{}, %{
            task_id: "task_1",
            file_path: "/project/untracked.ex",
            content_hash: hash,
            original_content_hash: orig_hash,
            status: "pending"
          })
        )

      Familiar.System.FileSystemMock
      |> expect(:read, fn "/project/untracked.ex" -> {:ok, content} end)

      # Git: file is NOT tracked
      Familiar.System.ShellMock
      |> expect(:cmd, fn "git", ["ls-files", "--error-unmatch", "/project/untracked.ex"], [] ->
        {:ok, %{output: "", exit_code: 1}}
      end)

      assert :ok = Files.rollback_task("task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "skipped"
    end

    test "rolls back delete of tracked file via git restore" do
      {:ok, _txn} =
        Repo.insert(
          Transaction.changeset(%Transaction{}, %{
            task_id: "task_1",
            file_path: "/project/deleted.ex",
            content_hash: "DELETE",
            original_content_hash: "orighash",
            status: "pending"
          })
        )

      # Git: file is tracked → restore
      Familiar.System.ShellMock
      |> expect(:cmd, fn "git", ["ls-files", "--error-unmatch", "/project/deleted.ex"], [] ->
        {:ok, %{output: "/project/deleted.ex", exit_code: 0}}
      end)
      |> expect(:cmd, fn "git", ["checkout", "HEAD", "--", "/project/deleted.ex"], [] ->
        {:ok, %{output: "", exit_code: 0}}
      end)

      assert :ok = Files.rollback_task("task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "rolled_back"
    end

    test "skips delete rollback when file was untracked" do
      {:ok, _txn} =
        Repo.insert(
          Transaction.changeset(%Transaction{}, %{
            task_id: "task_1",
            file_path: "/project/untracked.ex",
            content_hash: "DELETE",
            original_content_hash: "orighash",
            status: "pending"
          })
        )

      # Git: file is NOT tracked
      Familiar.System.ShellMock
      |> expect(:cmd, fn "git", ["ls-files", "--error-unmatch", "/project/untracked.ex"], [] ->
        {:ok, %{output: "", exit_code: 1}}
      end)

      assert :ok = Files.rollback_task("task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "skipped"
    end

    test "skips rollback when file was modified after write" do
      hash = Transaction.content_hash("original write")

      {:ok, _txn} =
        Repo.insert(
          Transaction.changeset(%Transaction{}, %{
            task_id: "task_1",
            file_path: "/project/modified.ex",
            content_hash: hash,
            status: "pending"
          })
        )

      Familiar.System.FileSystemMock
      |> expect(:read, fn "/project/modified.ex" -> {:ok, "user modified this"} end)

      assert :ok = Files.rollback_task("task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "skipped"
    end

    test "marks rolled_back when file doesn't exist (enoent)" do
      {:ok, _txn} =
        Repo.insert(
          Transaction.changeset(%Transaction{}, %{
            task_id: "task_1",
            file_path: "/project/gone.ex",
            content_hash: "somehash",
            status: "pending"
          })
        )

      Familiar.System.FileSystemMock
      |> expect(:read, fn "/project/gone.ex" ->
        {:error, {:file_error, %{reason: :enoent}}}
      end)

      assert :ok = Files.rollback_task("task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "rolled_back"
    end

    test "skips rollback on transient I/O error (not enoent)" do
      {:ok, _txn} =
        Repo.insert(
          Transaction.changeset(%Transaction{}, %{
            task_id: "task_1",
            file_path: "/project/locked.ex",
            content_hash: "somehash",
            status: "pending"
          })
        )

      Familiar.System.FileSystemMock
      |> expect(:read, fn "/project/locked.ex" ->
        {:error, {:file_error, %{reason: :eacces}}}
      end)

      assert :ok = Files.rollback_task("task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "skipped"
    end

    test "does not touch completed transactions" do
      {:ok, _txn} =
        Repo.insert(
          Transaction.changeset(%Transaction{}, %{
            task_id: "task_1",
            file_path: "/project/done.ex",
            content_hash: "hash",
            status: "completed"
          })
        )

      assert :ok = Files.rollback_task("task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "completed"
    end

    test "idempotent — re-running on rolled-back task is a no-op" do
      {:ok, _txn} =
        Repo.insert(
          Transaction.changeset(%Transaction{}, %{
            task_id: "task_1",
            file_path: "/project/done.ex",
            content_hash: "hash",
            status: "rolled_back"
          })
        )

      assert :ok = Files.rollback_task("task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "rolled_back"
    end

    test "also rolls back conflict records for the task" do
      {:ok, _txn} =
        Repo.insert(
          Transaction.changeset(%Transaction{}, %{
            task_id: "task_1",
            file_path: "/project/conflict.ex",
            content_hash: "hash",
            status: "conflict"
          })
        )

      # Conflict record treated as write rollback — file matches hash
      Familiar.System.FileSystemMock
      |> expect(:read, fn "/project/conflict.ex" ->
        {:error, {:file_error, %{reason: :enoent}}}
      end)

      assert :ok = Files.rollback_task("task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "rolled_back"
    end
  end

  # == Files.rollback_incomplete/0 ==

  describe "Files.rollback_incomplete/0" do
    test "rolls back all pending transactions across tasks" do
      for {task, path} <- [{"t1", "/a.ex"}, {"t2", "/b.ex"}] do
        Repo.insert!(
          Transaction.changeset(%Transaction{}, %{
            task_id: task,
            file_path: path,
            content_hash: "hash",
            status: "pending"
          })
        )
      end

      Familiar.System.FileSystemMock
      |> stub(:read, fn _p -> {:error, {:file_error, %{reason: :enoent}}} end)

      assert :ok = Files.rollback_incomplete()

      txns = Repo.all(Transaction)
      assert Enum.all?(txns, &(&1.status == "rolled_back"))
    end

    test "does not touch completed transactions" do
      Repo.insert!(
        Transaction.changeset(%Transaction{}, %{
          task_id: "t1",
          file_path: "/done.ex",
          content_hash: "hash",
          status: "completed"
        })
      )

      assert :ok = Files.rollback_incomplete()

      [txn] = Repo.all(Transaction)
      assert txn.status == "completed"
    end

    test "continues past individual rollback failures" do
      # Insert two pending transactions
      for {task, path} <- [{"t1", "/a.ex"}, {"t2", "/b.ex"}] do
        Repo.insert!(
          Transaction.changeset(%Transaction{}, %{
            task_id: task,
            file_path: path,
            content_hash: "hash",
            status: "pending"
          })
        )
      end

      # First read raises, second succeeds
      call_count = :counters.new(1, [:atomics])

      Familiar.System.FileSystemMock
      |> stub(:read, fn _path ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          raise "simulated I/O crash"
        else
          {:error, {:file_error, %{reason: :enoent}}}
        end
      end)

      # Should not crash — safe_rollback_one catches the exception
      assert :ok = Files.rollback_incomplete()

      # At least the second transaction should be rolled back
      txns = Repo.all(from(t in Transaction, where: t.status == "rolled_back"))
      assert txns != []
    end
  end

  # == Files.claimed_files/0 ==

  describe "Files.claimed_files/0" do
    test "returns map of active file claims" do
      Repo.insert!(
        Transaction.changeset(%Transaction{}, %{
          task_id: "t1",
          file_path: "/a.ex",
          content_hash: "h1",
          status: "pending"
        })
      )

      Repo.insert!(
        Transaction.changeset(%Transaction{}, %{
          task_id: "t2",
          file_path: "/b.ex",
          content_hash: "h2",
          status: "conflict"
        })
      )

      Repo.insert!(
        Transaction.changeset(%Transaction{}, %{
          task_id: "t3",
          file_path: "/c.ex",
          content_hash: "h3",
          status: "completed"
        })
      )

      claims = Files.claimed_files()
      assert claims == %{"/a.ex" => "t1", "/b.ex" => "t2"}
      refute Map.has_key?(claims, "/c.ex")
    end

    test "returns empty map when no active claims" do
      assert Files.claimed_files() == %{}
    end
  end

  # == Files.pending_conflicts/0 ==

  describe "Files.pending_conflicts/0" do
    test "returns conflict records" do
      Repo.insert!(
        Transaction.changeset(%Transaction{}, %{
          task_id: "t1",
          file_path: "/conflict.ex",
          content_hash: "h1",
          status: "conflict"
        })
      )

      Repo.insert!(
        Transaction.changeset(%Transaction{}, %{
          task_id: "t2",
          file_path: "/ok.ex",
          content_hash: "h2",
          status: "completed"
        })
      )

      conflicts = Files.pending_conflicts()
      assert length(conflicts) == 1
      assert hd(conflicts).file_path == "/conflict.ex"
    end

    test "returns empty list when no conflicts" do
      assert Files.pending_conflicts() == []
    end
  end

  # == Conflict Detection ==

  describe "conflict detection" do
    test "detects external modification and saves .fam-pending" do
      original = "original content"
      modified = "user modified this"
      new_content = "agent's version"

      read_count = :counters.new(1, [:atomics])

      Familiar.System.FileSystemMock
      |> stub(:read, fn "/project/foo.ex" ->
        count = :counters.get(read_count, 1)
        :counters.add(read_count, 1, 1)

        if count == 0 do
          {:ok, original}
        else
          {:ok, modified}
        end
      end)
      |> expect(:write, fn "/project/foo.ex.fam-pending", ^new_content -> :ok end)

      assert {:error, {:conflict, %{path: "/project/foo.ex"}}} =
               Files.write("/project/foo.ex", new_content, "task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "conflict"
    end

    test "logs warning when .fam-pending write fails" do
      original = "original content"
      modified = "user modified this"
      new_content = "agent's version"

      read_count = :counters.new(1, [:atomics])

      Familiar.System.FileSystemMock
      |> stub(:read, fn "/project/foo.ex" ->
        count = :counters.get(read_count, 1)
        :counters.add(read_count, 1, 1)
        if count == 0, do: {:ok, original}, else: {:ok, modified}
      end)
      |> expect(:write, fn "/project/foo.ex.fam-pending", _content ->
        {:error, {:file_error, %{reason: :enospc}}}
      end)

      # Still returns conflict error even when .fam-pending write fails
      assert {:error, {:conflict, %{path: "/project/foo.ex"}}} =
               Files.write("/project/foo.ex", new_content, "task_1")

      [txn] = Repo.all(Transaction)
      assert txn.status == "conflict"
    end

    test "no conflict when file unchanged between reads" do
      content = "stable content"
      new_content = "new version"

      Familiar.System.FileSystemMock
      |> stub(:read, fn "/project/foo.ex" -> {:ok, content} end)
      |> expect(:write, fn "/project/foo.ex", ^new_content -> :ok end)

      assert {:ok, txn} = Files.write("/project/foo.ex", new_content, "task_1")
      assert txn.status == "completed"
    end
  end

  # == Tool Integration ==

  describe "tool integration" do
    alias Familiar.Execution.Tools

    test "write_file routes through Files when task_id present" do
      Familiar.System.FileSystemMock
      |> stub(:read, fn _p -> {:error, {:file_error, %{reason: :enoent}}} end)
      |> expect(:write, fn "/project/foo.ex", "content" -> :ok end)

      context = %{task_id: "task_1", agent_id: "a1"}

      assert {:ok, %{path: "/project/foo.ex"}} =
               Tools.write_file(%{path: "/project/foo.ex", content: "content"}, context)

      [txn] = Repo.all(Transaction)
      assert txn.status == "completed"
    end

    test "write_file goes direct when no task_id" do
      Familiar.System.FileSystemMock
      |> expect(:write, fn "/project/foo.ex", "content" -> :ok end)

      context = %{agent_id: "a1"}

      assert {:ok, %{path: "/project/foo.ex"}} =
               Tools.write_file(%{path: "/project/foo.ex", content: "content"}, context)

      assert Repo.all(Transaction) == []
    end

    test "delete_file routes through Files when task_id present" do
      Familiar.System.FileSystemMock
      |> stub(:read, fn "/project/old.ex" -> {:ok, "content"} end)
      |> expect(:delete, fn "/project/old.ex" -> :ok end)

      context = %{task_id: "task_1", agent_id: "a1"}

      assert {:ok, %{path: "/project/old.ex"}} =
               Tools.delete_file(%{path: "/project/old.ex"}, context)

      [txn] = Repo.all(Transaction)
      assert txn.status == "completed"
    end

    test "delete_file goes direct when no task_id" do
      Familiar.System.FileSystemMock
      |> expect(:delete, fn "/project/old.ex" -> :ok end)

      context = %{agent_id: "a1"}

      assert {:ok, %{path: "/project/old.ex"}} =
               Tools.delete_file(%{path: "/project/old.ex"}, context)

      assert Repo.all(Transaction) == []
    end

    test "write_file returns fam-pending path on conflict" do
      original = "original"
      modified = "user changed"
      new_content = "agent version"

      read_count = :counters.new(1, [:atomics])

      Familiar.System.FileSystemMock
      |> stub(:read, fn "/project/foo.ex" ->
        count = :counters.get(read_count, 1)
        :counters.add(read_count, 1, 1)
        if count == 0, do: {:ok, original}, else: {:ok, modified}
      end)
      |> expect(:write, fn "/project/foo.ex.fam-pending", ^new_content -> :ok end)

      context = %{task_id: "task_1", agent_id: "a1"}

      assert {:ok, %{path: "/project/foo.ex.fam-pending", conflict: true}} =
               Tools.write_file(%{path: "/project/foo.ex", content: new_content}, context)
    end
  end

  # == StreamData Property Tests ==

  describe "property: rollback consistency" do
    property "rollback after write leaves no pending transactions" do
      check all(
              content <- binary(min_length: 1, max_length: 100),
              task_id <- string(:alphanumeric, min_length: 3, max_length: 10),
              path <- map(string(:alphanumeric, min_length: 3, max_length: 20), &"/prop/#{&1}.ex")
            ) do
        Familiar.System.FileSystemMock
        |> stub(:read, fn ^path -> {:error, {:file_error, %{reason: :enoent}}} end)
        |> stub(:write, fn ^path, ^content -> :ok end)

        case Files.write(path, content, task_id) do
          {:ok, txn} ->
            assert txn.status == "completed"
            assert :ok = Files.rollback_task(task_id)

          {:error, {:transaction_insert_failed, _}} ->
            :ok
        end

        Repo.delete_all(Transaction)
      end
    end

    property "rollback of pending writes marks all as rolled_back or skipped" do
      check all(
              num_files <- integer(1..5),
              task_id <- string(:alphanumeric, min_length: 3, max_length: 10),
              file_exists <- boolean()
            ) do
        for i <- 1..num_files do
          content = "content_#{i}"

          Repo.insert!(
            Transaction.changeset(%Transaction{}, %{
              task_id: task_id,
              file_path: "/prop/file_#{i}.ex",
              content_hash: Transaction.content_hash(content),
              status: "pending"
            })
          )
        end

        if file_exists do
          # Files exist and match hash — rollback deletes them
          Familiar.System.FileSystemMock
          |> stub(:read, fn "/prop/file_" <> rest ->
            i = rest |> String.trim_trailing(".ex") |> String.to_integer()
            {:ok, "content_#{i}"}
          end)
          |> stub(:delete, fn _path -> :ok end)
        else
          # Files don't exist
          Familiar.System.FileSystemMock
          |> stub(:read, fn _path -> {:error, {:file_error, %{reason: :enoent}}} end)
        end

        assert :ok = Files.rollback_task(task_id)

        txns = Repo.all(Transaction)
        assert Enum.all?(txns, &(&1.status in ["rolled_back", "skipped"]))

        Repo.delete_all(Transaction)
      end
    end

    property "content_hash is deterministic and collision-resistant" do
      check all(
              a <- binary(min_length: 1, max_length: 200),
              b <- binary(min_length: 1, max_length: 200)
            ) do
        hash_a = Transaction.content_hash(a)
        assert hash_a == Transaction.content_hash(a)
        assert String.length(hash_a) == 64

        if a != b do
          refute hash_a == Transaction.content_hash(b)
        end
      end
    end
  end

  # == File Claim Checking ==

  describe "claim checking" do
    defp insert_pending_claim(path, task_id) do
      %Transaction{}
      |> Transaction.changeset(%{
        task_id: task_id,
        file_path: path,
        content_hash: "abc123",
        original_content_hash: nil,
        status: "pending"
      })
      |> Familiar.Repo.insert!()
    end

    defp insert_claim(path, task_id, status) do
      %Transaction{}
      |> Transaction.changeset(%{
        task_id: task_id,
        file_path: path,
        content_hash: "abc123",
        original_content_hash: nil,
        status: status
      })
      |> Familiar.Repo.insert!()
    end

    test "write rejects when file is claimed by another task" do
      stub(Familiar.System.FileSystemMock, :read, fn _ -> {:error, {:file_error, %{reason: :enoent}}} end)

      insert_pending_claim("/project/foo.ex", "task_a")

      assert {:error, {:file_claimed, %{path: "/project/foo.ex", owner: "task_a"}}} =
               Files.write("/project/foo.ex", "content_b", "task_b")
    end

    test "delete rejects when file is claimed by another task" do
      stub(Familiar.System.FileSystemMock, :read, fn _ -> {:error, {:file_error, %{reason: :enoent}}} end)

      insert_pending_claim("/project/bar.ex", "task_a")

      assert {:error, {:file_claimed, %{path: "/project/bar.ex", owner: "task_a"}}} =
               Files.delete("/project/bar.ex", "task_b")
    end

    test "same task can re-write its own file" do
      stub(Familiar.System.FileSystemMock, :read, fn _ -> {:error, {:file_error, %{reason: :enoent}}} end)
      stub(Familiar.System.FileSystemMock, :write, fn _, _ -> :ok end)

      # First write succeeds
      assert {:ok, _} = Files.write("/project/same.ex", "v1", "task_a")

      # Same task writes again — passes claim check, clears stale completed row, succeeds
      assert {:ok, _} = Files.write("/project/same.ex", "v2", "task_a")
    end

    test "same task cannot re-write while previous write is still pending" do
      stub(Familiar.System.FileSystemMock, :read, fn _ -> {:error, {:file_error, %{reason: :enoent}}} end)

      insert_pending_claim("/project/pending.ex", "task_a")

      # Same task, but existing row is pending (not completed) — unique constraint fires
      assert {:error, {:transaction_insert_failed, _}} =
               Files.write("/project/pending.ex", "v2", "task_a")
    end

    test "completed transaction does not block new writes" do
      stub(Familiar.System.FileSystemMock, :read, fn _ -> {:error, {:file_error, %{reason: :enoent}}} end)
      stub(Familiar.System.FileSystemMock, :write, fn _, _ -> :ok end)

      insert_claim("/project/done.ex", "task_a", "completed")

      assert {:ok, _} = Files.write("/project/done.ex", "v2", "task_b")
    end

    test "rolled_back transaction does not block new writes" do
      stub(Familiar.System.FileSystemMock, :read, fn _ -> {:error, {:file_error, %{reason: :enoent}}} end)
      stub(Familiar.System.FileSystemMock, :write, fn _, _ -> :ok end)

      insert_claim("/project/rollback.ex", "task_a", "rolled_back")

      assert {:ok, _} = Files.write("/project/rollback.ex", "v2", "task_b")
    end

    test "conflict transaction blocks new writes (still active)" do
      stub(Familiar.System.FileSystemMock, :read, fn _ -> {:error, {:file_error, %{reason: :enoent}}} end)

      insert_claim("/project/conflict.ex", "task_a", "conflict")

      assert {:error, {:file_claimed, %{path: "/project/conflict.ex", owner: "task_a"}}} =
               Files.write("/project/conflict.ex", "content_b", "task_b")
    end
  end
end
