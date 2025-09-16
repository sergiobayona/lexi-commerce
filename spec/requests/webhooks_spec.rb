require 'rails_helper'
require 'sidekiq/testing'

RSpec.describe "Webhooks", type: :request do
  describe "GET /ingest" do
    let(:verify_token) { "test_verify_token_12345" }
    let(:challenge) { "challenge_string_67890" }

    # Helper method to stub environment variables
    def stub_env(key, value)
      allow(ENV).to receive(:fetch).with(key).and_return(value)
      allow(ENV).to receive(:fetch).with(key, anything).and_return(value)
    end

    before do
      stub_env("WHATSAPP_VERIFY_TOKEN", verify_token)
    end

    context "with valid verification parameters" do
      it "returns 200 OK with the challenge value" do
        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token,
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(challenge)
        expect(response.content_type).to include("text/plain")
      end

      it "handles URL-encoded parameters correctly" do
        get "/ingest?hub.mode=subscribe&hub.verify_token=#{verify_token}&hub.challenge=#{challenge}"

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(challenge)
      end

      it "ignores additional unexpected parameters" do
        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token,
          "hub.challenge": challenge,
          "extra_param": "should_be_ignored",
          "another_param": "also_ignored"
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(challenge)
      end

      it "handles special characters in challenge value" do
        special_challenge = "test+challenge/with=special&chars%20encoded"

        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token,
          "hub.challenge": special_challenge
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(special_challenge)
      end

      it "handles very long challenge values" do
        long_challenge = "x" * 1000

        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token,
          "hub.challenge": long_challenge
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(long_challenge)
      end

      it "returns empty body when challenge is missing but other params are valid" do
        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token
        }

        expect(response).to have_http_status(:ok)
        expect(response.body.strip).to be_empty
      end

      it "returns empty body when challenge is empty" do
        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token,
          "hub.challenge": ""
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to be_empty
      end
    end

    context "with invalid hub.mode" do
      it "returns 403 when hub.mode is not 'subscribe'" do
        get "/ingest", params: {
          "hub.mode": "unsubscribe",
          "hub.verify_token": verify_token,
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
        expect(response.body).to be_empty
      end

      it "returns 403 when hub.mode is missing" do
        get "/ingest", params: {
          "hub.verify_token": verify_token,
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
      end

      it "returns 403 when hub.mode is empty" do
        get "/ingest", params: {
          "hub.mode": "",
          "hub.verify_token": verify_token,
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
      end

      it "returns 403 when hub.mode has incorrect casing" do
        get "/ingest", params: {
          "hub.mode": "Subscribe", # Wrong casing
          "hub.verify_token": verify_token,
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
      end

      it "returns 403 when hub.mode is nil" do
        get "/ingest", params: {
          "hub.mode": nil,
          "hub.verify_token": verify_token,
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with invalid hub.verify_token" do
      it "returns 403 when verify_token doesn't match" do
        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": "wrong_token",
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
      end

      it "returns 403 when verify_token is missing" do
        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
      end

      it "returns 403 when verify_token is empty" do
        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": "",
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
      end

      it "returns 403 when verify_token is nil" do
        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": nil,
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
      end

      it "returns 403 when verify_token has extra characters" do
        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": "#{verify_token}_extra",
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
      end

      it "returns 403 when verify_token is partially correct" do
        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token[0..10], # Partial token
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with both invalid hub.mode and hub.verify_token" do
      it "returns 403 when both parameters are invalid" do
        get "/ingest", params: {
          "hub.mode": "invalid",
          "hub.verify_token": "wrong_token",
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
      end

      it "returns 403 when both parameters are missing" do
        get "/ingest", params: {
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "environment variable handling" do
      it "handles empty WHATSAPP_VERIFY_TOKEN environment variable" do
        stub_env("WHATSAPP_VERIFY_TOKEN", "")

        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": "",
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(challenge)
      end

      it "raises error when WHATSAPP_VERIFY_TOKEN is not set" do
        allow(ENV).to receive(:fetch).with("WHATSAPP_VERIFY_TOKEN").and_raise(KeyError)

        expect {
          get "/ingest", params: {
            "hub.mode": "subscribe",
            "hub.verify_token": "any_token",
            "hub.challenge": challenge
          }
        }.to raise_error(KeyError)
      end

      it "handles whitespace in WHATSAPP_VERIFY_TOKEN" do
        stub_env("WHATSAPP_VERIFY_TOKEN", "  token_with_spaces  ")

        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": "  token_with_spaces  ",
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(challenge)
      end
    end

    context "parameter name variations" do
      it "handles parameters with different casing (should fail)" do
        # Testing that parameter names are case-sensitive
        get "/ingest", params: {
          "Hub.Mode": "subscribe",
          "Hub.Verify_Token": verify_token,
          "Hub.Challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
      end

      it "handles parameters with underscores instead of dots (should fail)" do
        get "/ingest", params: {
          "hub_mode": "subscribe",
          "hub_verify_token": verify_token,
          "hub_challenge": challenge
        }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "edge cases" do
      it "handles numeric challenge values" do
        numeric_challenge = "123456789"

        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token,
          "hub.challenge": numeric_challenge
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(numeric_challenge)
      end

      it "handles challenge with unicode characters" do
        unicode_challenge = "test_😀_challenge_文字"

        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token,
          "hub.challenge": unicode_challenge
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(unicode_challenge)
      end

      it "handles challenge with newlines and tabs" do
        multiline_challenge = "test\nchallenge\twith\rspecial\nchars"

        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token,
          "hub.challenge": multiline_challenge
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(multiline_challenge)
      end

      it "handles JSON-like string in challenge" do
        json_challenge = '{"test":"value","array":[1,2,3]}'

        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token,
          "hub.challenge": json_challenge
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(json_challenge)
      end
    end

    context "security and side effects" do
      it "does not create any database records" do
        expect {
          get "/ingest", params: {
            "hub.mode": "subscribe",
            "hub.verify_token": verify_token,
            "hub.challenge": challenge
          }
        }.not_to change { WebhookEvent.count }
      end

      it "does not enqueue any background jobs" do
        # GET /ingest should not trigger any job processing
        # This is a simple verification endpoint with no side effects
        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token,
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:ok)
        # No job queues are involved in the verification process
      end

      it "does not require authentication" do
        # No auth headers needed
        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token,
          "hub.challenge": challenge
        }

        expect(response).to have_http_status(:ok)
      end

      it "handles SQL injection attempts in parameters safely" do
        sql_injection_attempt = "'; DROP TABLE users; --"

        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token,
          "hub.challenge": sql_injection_attempt
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(sql_injection_attempt)
        # Verify tables still exist
        expect { WebhookEvent.count }.not_to raise_error
      end

      it "handles XSS attempts in challenge safely" do
        xss_attempt = "<script>alert('XSS')</script>"

        get "/ingest", params: {
          "hub.mode": "subscribe",
          "hub.verify_token": verify_token,
          "hub.challenge": xss_attempt
        }

        expect(response).to have_http_status(:ok)
        # Response should be plain text, not HTML
        expect(response.content_type).to include("text/plain")
        expect(response.body).to eq(xss_attempt)
      end
    end
  end
end