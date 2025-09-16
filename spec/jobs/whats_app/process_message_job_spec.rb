# spec/jobs/whatsapp/process_message_job_spec.rb
require "rails_helper"

RSpec.describe Whatsapp::ProcessMessageJob, type: :job do
  let(:value) do
    { "messaging_product" => "whatsapp",
      "metadata" => { "display_phone_number" => "15550000000", "phone_number_id" => "111" },
      "contacts" => [ { "wa_id" => "16505551234", "profile" => { "name" => "Alice" } } ]
    }
  end

  it "calls TextProcessor for text" do
    msg = { "id" => "wamid.1", "timestamp" => "1749416383", "type" => "text", "text" => { "body" => "hi" } }
    expect(Whatsapp::Processors::TextProcessor)
      .to receive(:new).with(value, msg).and_call_original
    expect_any_instance_of(Whatsapp::Processors::TextProcessor)
      .to receive(:call)

    described_class.perform_now(value, msg)
  end

  it "calls AudioProcessor for audio" do
    msg = { "id" => "wamid.2", "timestamp" => "1749416383", "type" => "audio", "audio" => { "id" => "media.9", "sha256" => "abc", "mime_type" => "audio/ogg" } }
    expect(Whatsapp::Processors::AudioProcessor)
      .to receive(:new).with(value, msg).and_call_original
    expect_any_instance_of(Whatsapp::Processors::AudioProcessor)
      .to receive(:call)

    described_class.perform_now(value, msg)
  end
end
