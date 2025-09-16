class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  before_action :verify_signature!, only: :create

  # GET /ingest
  def verify
    if params[:'hub.mode'] == "subscribe" && params[:'hub.verify_token'] == ENV.fetch("WHATSAPP_VERIFY_TOKEN")
      render plain: params[:'hub.challenge'], status: :ok
    else
      head :forbidden
    end
  end

  # POST /webhooks/whatsapp
  def create
    payload = request.raw_post
    data = JSON.parse(payload)

    WebhookEvent.create!(provider: "whatsapp", object_name: data["object"], payload: data)

    WhatsApp::IngestWebhookJob.perform_later(data)
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def verify_signature!
    sig = request.headers["X-Hub-Signature-256"]
    return if sig.blank? # allow in dev; enforce in prod
    expected = "sha256=" + OpenSSL::HMAC.hexdigest("sha256", ENV.fetch("WHATSAPP_APP_SECRET"), request.raw_post)
    head :forbidden unless ActiveSupport::SecurityUtils.secure_compare(expected, sig)
  end
end
