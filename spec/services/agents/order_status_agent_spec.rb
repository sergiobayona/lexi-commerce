# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::OrderStatusAgent do
  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:mock_response) { instance_double(RubyLLM::Message) }

  # Agent must be created AFTER mocking RubyLLM
  let(:agent) do
    # Mock RubyLLM before creating agent
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:with_tool).and_return(mock_chat)
    allow(mock_chat).to receive(:with_tools).and_return(mock_chat)
    allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
    allow(mock_chat).to receive(:on_tool_call).and_return(mock_chat)
    allow(mock_chat).to receive(:respond_to?).and_call_original
    allow(mock_chat).to receive(:respond_to?).with(:with_tools).and_return(true)
    allow(mock_chat).to receive(:respond_to?).with(:on_tool_result).and_return(true)
    allow(mock_chat).to receive(:on_tool_result).and_return(mock_chat)

    described_class.new
  end

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
          # Mock LLM response for order tracking
          allow(mock_response).to receive(:content).and_return("Su Orden #12345 está en tránsito")
          allow(mock_chat).to receive(:ask).and_return(mock_response)

          turn = base_turn.merge(text: "Track order #12345")
          response = agent.handle(turn: turn, state: verified_state, intent: "track_order")

          expect(response.messages).to be_an(Array)
          expect(response.messages.first[:text][:body]).to include("Orden #12345")
          expect(response.state_patch.dig("order", "last_interaction")).to be_present
        end

        it "requests order number when not provided" do
          # Mock LLM response requesting order number
          allow(mock_response).to receive(:content).and_return("Por favor, proporcione el número de su orden para rastrearla")
          allow(mock_chat).to receive(:ask).and_return(mock_response)

          turn = base_turn.merge(text: "Track my order")
          response = agent.handle(turn: turn, state: verified_state, intent: "track_order")

          expect(response.messages.first[:text][:body]).to include("número de su orden")
        end
      end

      context "when customer is not verified" do
        it "requests verification" do
          # Mock LLM response requesting verification
          allow(mock_response).to receive(:content).and_return("Necesito verificar su identidad antes de proporcionar información de la orden")
          allow(mock_chat).to receive(:ask).and_return(mock_response)

          response = agent.handle(turn: base_turn, state: unverified_state, intent: "track_order")

          expect(response.messages.first[:text][:body]).to include("verificar su identidad")
          expect(response.state_patch.dig("order", "last_interaction")).to be_present
        end
      end
    end

    context "with order_status intent" do
      context "when customer is verified" do
        it "shows status of most recent order" do
          # Mock LLM response with order status
          allow(mock_response).to receive(:content).and_return("Su orden ORD-12345 está en tránsito. Llegará pronto.")
          allow(mock_chat).to receive(:ask).and_return(mock_response)

          response = agent.handle(turn: base_turn, state: verified_state, intent: "order_status")

          expect(response.messages.first[:text][:body]).to include("ORD-12345")
          expect(response.messages.first[:text][:body]).to include("tránsito")
        end

        it "handles case with no recent orders" do
          # Mock LLM response for no orders
          allow(mock_response).to receive(:content).and_return("No tiene órdenes recientes en nuestro sistema.")
          allow(mock_chat).to receive(:ask).and_return(mock_response)

          state = verified_state.merge("last_order_id" => nil)
          response = agent.handle(turn: base_turn, state: state, intent: "order_status")

          expect(response.messages.first[:text][:body]).to include("No tiene órdenes recientes")
        end
      end

      context "when customer is not verified" do
        it "requests verification" do
          # Mock LLM response requesting verification
          allow(mock_response).to receive(:content).and_return("Necesito verificar su identidad antes de mostrar el estado de su orden")
          allow(mock_chat).to receive(:ask).and_return(mock_response)

          response = agent.handle(turn: base_turn, state: unverified_state, intent: "order_status")

          expect(response.messages.first[:text][:body]).to include("verificar su identidad")
        end
      end
    end

    context "with delivery_eta intent" do
      it "provides estimated delivery time for verified customer" do
        # Mock LLM response with ETA
        allow(mock_response).to receive(:content).and_return("Su pedido llegará en aproximadamente 2-3 días hábiles")
        allow(mock_chat).to receive(:ask).and_return(mock_response)

        response = agent.handle(turn: base_turn, state: verified_state, intent: "delivery_eta")

        expect(response.messages.first[:text][:body]).to include("2-3 días hábiles")
        expect(response.state_patch.dig("order", "last_interaction")).to be_present
      end

      it "requests verification for unverified customer" do
        # Mock LLM response requesting verification
        allow(mock_response).to receive(:content).and_return("Necesito verificar su identidad para proporcionar el ETA")
        allow(mock_chat).to receive(:ask).and_return(mock_response)

        response = agent.handle(turn: base_turn, state: unverified_state, intent: "delivery_eta")

        expect(response.messages.first[:text][:body]).to include("verificar su identidad")
      end
    end

    context "with shipping_update intent" do
      it "provides tracking information for verified customer" do
        # Mock LLM response with tracking info
        allow(mock_response).to receive(:content).and_return("Aquí está el número de rastreo: TRK123456")
        allow(mock_chat).to receive(:ask).and_return(mock_response)

        response = agent.handle(turn: base_turn, state: verified_state, intent: "shipping_update")

        expect(response.messages.first[:text][:body]).to include("rastreo")
        expect(response.state_patch.dig("order", "last_interaction")).to be_present
      end

      it "requests verification for unverified customer" do
        # Mock LLM response requesting verification
        allow(mock_response).to receive(:content).and_return("Necesito verificar su identidad antes de proporcionar información de rastreo")
        allow(mock_chat).to receive(:ask).and_return(mock_response)

        response = agent.handle(turn: base_turn, state: unverified_state, intent: "shipping_update")

        expect(response.messages.first[:text][:body]).to include("verificar su identidad")
      end
    end

    context "with unknown intent" do
      it "provides general order inquiry help" do
        # Mock LLM response with help text
        allow(mock_response).to receive(:content).and_return("Puedo ayudarle con: Rastrear su orden, Ver estado de pedidos, Información de entrega")
        allow(mock_chat).to receive(:ask).and_return(mock_response)

        response = agent.handle(turn: base_turn, state: verified_state, intent: "general")

        expect(response.messages.first[:text][:body]).to include("Puedo ayudarle con")
        expect(response.messages.first[:text][:body]).to include("Rastrear su orden")
      end
    end
  end

  # Note: OrderStatusAgent uses RubyLLM with tools for order lookup and verification.
  # The agent relies on OrderLookup, ShippingStatus, and DeliveryEstimate tools
  # which handle order number extraction and customer verification automatically.

  describe "inheritance" do
    it "inherits from BaseAgent" do
      expect(agent).to be_a(Agents::BaseAgent)
    end

    it "mixes in tool-enabled behaviour" do
      expect(agent).to be_a(Agents::ToolEnabledAgent)
    end

    it "responds to handle method" do
      expect(agent).to respond_to(:handle)
    end
  end
end
