defmodule Familiar.Knowledge.SecretFilterTest do
  use ExUnit.Case, async: true

  alias Familiar.Knowledge.SecretFilter

  describe "filter/1" do
    test "strips AWS access keys" do
      text = "Uses AKIAIOSFODNN7EXAMPLE for S3 access"
      result = SecretFilter.filter(text)
      refute result =~ "AKIAIOSFODNN7EXAMPLE"
      assert result =~ "[AWS_ACCESS_KEY]"
    end

    test "strips Stripe secret keys" do
      text = "Configured with sk_live_abcdefghijklmnopqrstuvwxyz"
      result = SecretFilter.filter(text)
      refute result =~ "sk_live_"
      assert result =~ "[STRIPE_SECRET_KEY]"
    end

    test "strips GitHub tokens" do
      text = "Auth via ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklm"
      result = SecretFilter.filter(text)
      refute result =~ "ghp_"
      assert result =~ "[GITHUB_TOKEN]"
    end

    test "strips URLs with embedded credentials" do
      text = "Connects to postgres://admin:s3cret@localhost/db"
      result = SecretFilter.filter(text)
      refute result =~ "s3cret"
      assert result =~ "[CREDENTIALS]"
    end

    test "strips env var assignments" do
      text = "DATABASE_URL=postgres://localhost/mydb SECRET_KEY=abc123"
      result = SecretFilter.filter(text)
      assert result =~ "DATABASE_URL=[REDACTED]"
      assert result =~ "SECRET_KEY=[REDACTED]"
    end

    test "strips long base64 tokens with padding" do
      token = String.duplicate("A", 80) <> "=="
      text = "Token: #{token}"
      result = SecretFilter.filter(text)
      assert result =~ "[REDACTED_TOKEN]"
    end

    test "preserves normal text" do
      text = "This module handles user authentication and session management"
      assert text == SecretFilter.filter(text)
    end

    test "does not redact short alphanumeric strings (no false positives)" do
      # Git hashes, UUIDs, and moderate-length identifiers should be preserved
      text = "Commit abc123def456789012345678901234567890 in main branch"
      assert text == SecretFilter.filter(text)
    end

    test "handles nil-like input gracefully" do
      assert nil == SecretFilter.filter(nil)
    end
  end
end
