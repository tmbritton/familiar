defmodule Familiar.Knowledge.ContentValidatorTest do
  use ExUnit.Case, async: true

  alias Familiar.Knowledge.ContentValidator

  describe "validate_not_code/1" do
    # -- Should ACCEPT prose descriptions --

    test "accepts prose about code behavior" do
      assert {:ok, _} =
               ContentValidator.validate_not_code(
                 "The auth module uses JWT tokens with 24-hour expiry for API authentication."
               )
    end

    test "accepts convention descriptions" do
      assert {:ok, _} =
               ContentValidator.validate_not_code(
                 "All controllers follow the single-action pattern with one public function per module."
               )
    end

    test "accepts relationship descriptions" do
      assert {:ok, _} =
               ContentValidator.validate_not_code(
                 "The User schema belongs_to Organization through team membership."
               )
    end

    test "accepts prose with inline code references" do
      assert {:ok, _} =
               ContentValidator.validate_not_code(
                 "Uses `GenServer.call/2` for synchronous requests and `cast/2` for async fire-and-forget."
               )
    end

    test "accepts short factual statements" do
      assert {:ok, _} =
               ContentValidator.validate_not_code("Database uses PostgreSQL 15 with pg_vector extension.")
    end

    test "accepts multi-line prose" do
      text = """
      The notification system supports multiple providers: email, Slack, and webhooks.
      Each provider implements the NotificationSender behaviour.
      Failed notifications are retried up to 3 times with exponential backoff.
      """

      assert {:ok, _} = ContentValidator.validate_not_code(text)
    end

    # -- Should REJECT raw code --

    test "rejects Elixir module definition" do
      code = """
      defmodule MyApp.Auth do
        def verify_token(token) do
          case JWT.decode(token) do
            {:ok, claims} -> {:ok, claims}
            {:error, _} -> {:error, :invalid_token}
          end
        end
      end
      """

      assert {:error, {:knowledge_not_code, %{reason: _}}} =
               ContentValidator.validate_not_code(code)
    end

    test "rejects JavaScript function" do
      code = """
      function authenticate(req, res, next) {
        const token = req.headers.authorization;
        if (!token) {
          return res.status(401).json({ error: 'Unauthorized' });
        }
        next();
      }
      """

      assert {:error, {:knowledge_not_code, %{reason: _}}} =
               ContentValidator.validate_not_code(code)
    end

    test "rejects Go function" do
      code = """
      func (s *Server) HandleLogin(w http.ResponseWriter, r *http.Request) {
        var creds Credentials
        if err := json.NewDecoder(r.Body).Decode(&creds); err != nil {
          http.Error(w, "Bad request", http.StatusBadRequest)
          return
        }
      }
      """

      assert {:error, {:knowledge_not_code, %{reason: _}}} =
               ContentValidator.validate_not_code(code)
    end

    test "rejects Python function" do
      code = """
      def authenticate(request):
          token = request.headers.get('Authorization')
          if not token:
              raise AuthenticationError('Missing token')
          payload = jwt.decode(token, settings.SECRET_KEY)
          return payload
      """

      assert {:error, {:knowledge_not_code, %{reason: _}}} =
               ContentValidator.validate_not_code(code)
    end

    test "rejects Rust function" do
      code = """
      impl AuthService {
          pub fn verify(&self, token: &str) -> Result<Claims, AuthError> {
              let decoded = decode::<Claims>(token, &self.key, &Validation::default())?;
              Ok(decoded.claims)
          }
      }
      """

      assert {:error, {:knowledge_not_code, %{reason: _}}} =
               ContentValidator.validate_not_code(code)
    end

    test "rejects import-heavy content" do
      code = """
      import React from 'react';
      import { useState, useEffect } from 'react';
      import { AuthContext } from './context';
      import { validateToken } from '../utils/auth';
      import { API_BASE_URL } from '../config';
      """

      assert {:error, {:knowledge_not_code, %{reason: _}}} =
               ContentValidator.validate_not_code(code)
    end

    # -- Edge cases --

    test "accepts content at 59% code lines (below threshold)" do
      # 3 code lines out of 5 non-blank lines = 60%, but we need under 60%
      # 2 code lines out of 5 = 40% — should pass
      text = """
      This module handles user authentication.
      It validates JWT tokens on every request.
      def verify(token) do
      The expiry is configurable via environment variables.
      Tokens are rotated every 24 hours.
      """

      assert {:ok, _} = ContentValidator.validate_not_code(text)
    end

    test "rejects content at 60% code lines (at threshold)" do
      # 3 code lines out of 5 = 60% — should be rejected
      text = """
      def authenticate(user) do
      This is a prose description line.
      case verify(user.token) do
      Another prose description line.
      end
      """

      assert {:error, {:knowledge_not_code, _}} = ContentValidator.validate_not_code(text)
    end

    test "handles CRLF line endings correctly" do
      code = "defmodule Foo do\r\n  def bar, do: :ok\r\n  def baz, do: :ok\r\nend\r\n"

      assert {:error, {:knowledge_not_code, _}} = ContentValidator.validate_not_code(code)
    end

    test "rejects empty string" do
      assert {:error, {:knowledge_not_code, %{reason: _}}} =
               ContentValidator.validate_not_code("")
    end

    test "rejects whitespace-only string" do
      assert {:error, {:knowledge_not_code, %{reason: _}}} =
               ContentValidator.validate_not_code("   \n  \n  ")
    end

    test "returns the original text on success" do
      text = "Module handles authentication via JWT tokens."
      assert {:ok, ^text} = ContentValidator.validate_not_code(text)
    end
  end
end
