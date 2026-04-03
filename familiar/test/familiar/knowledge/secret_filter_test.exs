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

    test "strips base64 tokens at exactly 40 chars with padding" do
      token = String.duplicate("A", 40) <> "=="
      text = "Token: #{token}"
      result = SecretFilter.filter(text)
      assert result =~ "[REDACTED_TOKEN]"
      refute result =~ token
    end

    test "does not strip base64-like strings under 40 chars" do
      token = String.duplicate("A", 39) <> "=="
      text = "Short token: #{token}"
      assert text == SecretFilter.filter(text)
    end

    test "strips long base64 tokens (80+ chars)" do
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
      text = "Commit abc123def456789012345678901234567890 in main branch"
      assert text == SecretFilter.filter(text)
    end

    test "does not redact git hashes (40 hex chars, no = padding)" do
      text = "Commit 5b29137abcdef1234567890abcdef1234567890ab resolved"
      assert text == SecretFilter.filter(text)
    end

    test "does not redact env var names without values" do
      text = "The DATABASE_URL variable is configured in production"
      assert text == SecretFilter.filter(text)
    end

    test "filters multiple different secret types in one pass" do
      text = "AWS key AKIAIOSFODNN7EXAMPLE and token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklm"
      result = SecretFilter.filter(text)
      assert result =~ "[AWS_ACCESS_KEY]"
      assert result =~ "[GITHUB_TOKEN]"
      refute result =~ "AKIAIOSFODNN7EXAMPLE"
      refute result =~ "ghp_"
    end

    test "idempotent — filtering already-filtered text produces same result" do
      text = "Uses AKIAIOSFODNN7EXAMPLE for S3"
      once = SecretFilter.filter(text)
      twice = SecretFilter.filter(once)
      assert once == twice
    end

    test "handles empty string" do
      assert "" == SecretFilter.filter("")
    end

    test "handles whitespace-only string" do
      assert "   " == SecretFilter.filter("   ")
    end

    test "handles nil-like input gracefully" do
      assert nil == SecretFilter.filter(nil)
    end

    test "strips Stripe publishable keys" do
      text = "Frontend uses pk_live_abcdefghijklmnopqrstuvwxyz"
      result = SecretFilter.filter(text)
      refute result =~ "pk_live_"
      assert result =~ "[STRIPE_PUBLISHABLE_KEY]"
    end

    test "strips GitHub OAuth tokens" do
      text = "OAuth via gho_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklm"
      result = SecretFilter.filter(text)
      refute result =~ "gho_"
      assert result =~ "[GITHUB_OAUTH_TOKEN]"
    end

    test "strips unpadded base64 tokens with uppercase letters" do
      # Mixed case base64 without = padding — should be caught
      token = "ABCDEFabcdef0123456789ABCDEFabcdef01234567"
      text = "Token: #{token}"
      result = SecretFilter.filter(text)
      assert result =~ "[REDACTED_TOKEN]"
    end

    test "strips unpadded base64 tokens with + or / characters" do
      token = "abcdef+ghijkl/mnopqr0123456789abcdef01234567"
      text = "Token: #{token}"
      result = SecretFilter.filter(text)
      assert result =~ "[REDACTED_TOKEN]"
    end

    test "strips all env var pattern types" do
      for var <-
            ~w(DATABASE_URL SECRET_KEY_BASE API_KEY SECRET_KEY PRIVATE_KEY ACCESS_TOKEN AUTH_TOKEN) do
        text = "#{var}=some_secret_value_123"
        result = SecretFilter.filter(text)
        assert result =~ "[REDACTED]", "Expected #{var} to be redacted"
        refute result =~ "some_secret_value_123", "Expected value of #{var} to be removed"
      end
    end
  end

  describe "contains_secrets?/1" do
    test "returns true when text contains a secret" do
      assert SecretFilter.contains_secrets?("Key is AKIAIOSFODNN7EXAMPLE")
    end

    test "returns false for safe text" do
      refute SecretFilter.contains_secrets?("Normal text about authentication")
    end

    test "returns false for nil" do
      refute SecretFilter.contains_secrets?(nil)
    end

    test "returns false for empty string" do
      refute SecretFilter.contains_secrets?("")
    end

    test "detects Stripe keys" do
      assert SecretFilter.contains_secrets?("Key: sk_live_abcdefghijklmnopqrstuvwxyz")
    end

    test "detects GitHub tokens" do
      assert SecretFilter.contains_secrets?("Token: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklm")
    end

    test "detects URLs with credentials" do
      assert SecretFilter.contains_secrets?("postgres://admin:s3cret@localhost/db")
    end

    test "detects env var assignments" do
      assert SecretFilter.contains_secrets?("API_KEY=some_value")
    end

    test "detects base64 tokens with padding" do
      token = String.duplicate("A", 40) <> "=="
      assert SecretFilter.contains_secrets?("Token: #{token}")
    end
  end

  describe "detect/1" do
    test "returns matched pattern names and values" do
      text = "Key is AKIAIOSFODNN7EXAMPLE"
      detections = SecretFilter.detect(text)
      assert length(detections) == 1
      assert {"[AWS_ACCESS_KEY]", "AKIAIOSFODNN7EXAMPLE"} in detections
    end

    test "returns multiple detections for multiple secrets" do
      text = "AWS AKIAIOSFODNN7EXAMPLE and Stripe sk_live_abcdefghijklmnopqrstuvwxyz"
      detections = SecretFilter.detect(text)
      assert length(detections) == 2
    end

    test "returns empty list for safe text" do
      assert [] == SecretFilter.detect("Normal project description")
    end

    test "returns empty list for nil" do
      assert [] == SecretFilter.detect(nil)
    end

    test "detects all supported pattern types" do
      # AWS
      assert [{"[AWS_ACCESS_KEY]", _}] = SecretFilter.detect("AKIAIOSFODNN7EXAMPLE")
      # Stripe secret
      assert [{"[STRIPE_SECRET_KEY]", _}] =
               SecretFilter.detect("sk_live_abcdefghijklmnopqrstuvwxyz")

      # Stripe publishable
      assert [{"[STRIPE_PUBLISHABLE_KEY]", _}] =
               SecretFilter.detect("pk_live_abcdefghijklmnopqrstuvwxyz")

      # GitHub token
      assert [{"[GITHUB_TOKEN]", _}] =
               SecretFilter.detect("ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklm")

      # GitHub OAuth
      assert [{"[GITHUB_OAUTH_TOKEN]", _}] =
               SecretFilter.detect("gho_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklm")

      # URL credentials
      assert [{"://[CREDENTIALS]@", _}] = SecretFilter.detect("postgres://admin:secret@host")
      # Env var
      detections = SecretFilter.detect("API_KEY=myvalue")
      assert Enum.any?(detections, fn {pattern, _} -> pattern =~ "REDACTED" end)
    end
  end
end
