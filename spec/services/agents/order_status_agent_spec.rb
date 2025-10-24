# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::OrderStatusAgent do
  let(:agent) { described_class.new }

  let(:base_turn) do
    {
      tenant_id: "test_tenant",
      wa_id: "1234567890",
      message_id: "msg_123",
      text: "Where is my order?",
      payload: nil,
      timestamp: Time.now.utc.iso8601
    }
  end

  let(:verified_state) do
    {
      "tenant_id" => "test_tenant",
      "wa_id" => "1234567890",
      "phone_verified" => true,
      "customer_id" => "cust_123",
      "last_order_id" => "ORD-12345"
    }
  end

  let(:unverified_state) do
    {
      "tenant_id" => "test_tenant",
      "wa_id" => "1234567890",
      "phone_verified" => false,
      "customer_id" => nil
    }
  end

  describe "#handle" do
    context "with track_order intent" do
      context "when customer is verified" do
        it "queries order status when order number provided" do
          turn = base_turn.merge(text: "Track order #12345")
          response = agent.handle(turn: turn, state: verified_state, intent: "track_order")

          expect(response.messages).to be_an(Array)
          expect(response.messages.first[:text][:body]).to include("Orden #12345")
          expect(response.state_patch["last_order_checked"]).to eq("12345")
        end

        it "requests order number when not provided" do
          turn = base_turn.merge(text: "Track my order")
          response = agent.handle(turn: turn, state: verified_state, intent: "track_order")

          expect(response.messages.first[:text][:body]).to include("número de su orden")
        end
      end

      context "when customer is not verified" do
        it "requests verification" do
          response = agent.handle(turn: base_turn, state: unverified_state, intent: "track_order")

          expect(response.messages.first[:text][:body]).to include("verificar su identidad")
          expect(response.state_patch["verification_requested"]).to be true
        end
      end
    end

    context "with order_status intent" do
      context "when customer is verified" do
        it "shows status of most recent order" do
          response = agent.handle(turn: base_turn, state: verified_state, intent: "order_status")

          expect(response.messages.first[:text][:body]).to include("ORD-12345")
          expect(response.messages.first[:text][:body]).to include("tránsito")
        end

        it "handles case with no recent orders" do
          state = verified_state.merge("last_order_id" => nil)
          response = agent.handle(turn: base_turn, state: state, intent: "order_status")

          expect(response.messages.first[:text][:body]).to include("No tiene órdenes recientes")
        end
      end

      context "when customer is not verified" do
        it "requests verification" do
          response = agent.handle(turn: base_turn, state: unverified_state, intent: "order_status")

          expect(response.messages.first[:text][:body]).to include("verificar su identidad")
        end
      end
    end

    context "with delivery_eta intent" do
      it "provides estimated delivery time for verified customer" do
        response = agent.handle(turn: base_turn, state: verified_state, intent: "delivery_eta")

        expect(response.messages.first[:text][:body]).to include("2-3 días hábiles")
        expect(response.state_patch["last_interaction"]).to be_present
      end

      it "requests verification for unverified customer" do
        response = agent.handle(turn: base_turn, state: unverified_state, intent: "delivery_eta")

        expect(response.messages.first[:text][:body]).to include("verificar su identidad")
      end
    end

    context "with shipping_update intent" do
      it "provides tracking information for verified customer" do
        response = agent.handle(turn: base_turn, state: verified_state, intent: "shipping_update")

        expect(response.messages.first[:text][:body]).to include("rastreo")
        expect(response.state_patch["last_interaction"]).to be_present
      end

      it "requests verification for unverified customer" do
        response = agent.handle(turn: base_turn, state: unverified_state, intent: "shipping_update")

        expect(response.messages.first[:text][:body]).to include("verificar su identidad")
      end
    end

    context "with unknown intent" do
      it "provides general order inquiry help" do
        response = agent.handle(turn: base_turn, state: verified_state, intent: "general")

        expect(response.messages.first[:text][:body]).to include("Puedo ayudarle con")
        expect(response.messages.first[:text][:body]).to include("Rastrear su orden")
      end
    end
  end

  describe "#extract_order_number" do
    it "extracts order number with hash prefix" do
      result = agent.send(:extract_order_number, "Track order #12345")
      expect(result).to eq("12345")
    end

    it "extracts order number with ORD prefix" do
      result = agent.send(:extract_order_number, "Where is ORD-67890?")
      expect(result).to eq("ORD-67890")
    end

    it "extracts standalone number" do
      result = agent.send(:extract_order_number, "Order 98765")
      expect(result).to eq("98765")
    end

    it "returns nil when no order number found" do
      result = agent.send(:extract_order_number, "Where is my order?")
      expect(result).to be_nil
    end
  end

  describe "#verified_customer?" do
    it "returns true when phone verified and customer_id present" do
      result = agent.send(:verified_customer?, verified_state)
      expect(result).to be true
    end

    it "returns false when phone not verified" do
      state = verified_state.merge("phone_verified" => false)
      result = agent.send(:verified_customer?, state)
      expect(result).to be false
    end

    it "returns false when customer_id missing" do
      state = verified_state.merge("customer_id" => nil)
      result = agent.send(:verified_customer?, state)
      expect(result).to be false
    end

    it "returns false when both missing" do
      result = agent.send(:verified_customer?, unverified_state)
      expect(result).to be false
    end
  end

  describe "inheritance" do
    it "inherits from BaseAgent" do
      expect(agent).to be_a(Agents::BaseAgent)
    end

    it "responds to handle method" do
      expect(agent).to respond_to(:handle)
    end
  end
end
