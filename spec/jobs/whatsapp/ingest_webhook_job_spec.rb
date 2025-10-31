# spec/jobs/whatsapp/ingest_webhook_job_spec.rb
require "rails_helper"

RSpec.describe Whatsapp::IngestWebhookJob, type: :job do
  it "enqueues one ProcessMessageJob per message" do
    payload = json_fixture("whatsapp/multi_messages.json")
    expect {
      described_class.perform_now(payload)
    }.to have_enqueued_job(Whatsapp::ProcessMessageJob).exactly(3).times
  end

  it "skips non-whatsapp products and missing messages" do
    payload = {
      "entry" => [ {
        "changes" => [
          { "value" => { "messaging_product" => "instagram" } },
          { "value" => { "messaging_product" => "whatsapp", "messages" => [] } }
        ]
      } ]
    }
    expect {
      described_class.perform_now(payload)
    }.not_to have_enqueued_job(Whatsapp::ProcessMessageJob)
  end
end
