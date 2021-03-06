require 'spec_helper'

module QBIntegration
  module Service
    describe PaymentMethod do
      let(:payload) do
        {
          "order" => Factories.order
        }.with_indifferent_access
      end

      let(:message) do
        { :payload => payload }.with_indifferent_access
      end

      let(:config) do
        {
          'quickbooks_realm' => "123",
          'quickbooks_access_token' => "123",
          'quickbooks_access_secret' => "123"
        }
      end

      subject { PaymentMethod.new config, payload }

      context ".augury_name" do
        it "picks credit card if provided" do
          message[:payload][:order][:payments][0][:payment_method] = "Visa"
          expect(subject.augury_name).to eq "Visa"
        end

        it "picks payment method name if credit card not provided" do
          message[:payload][:order][:credit_cards] = []
          expect(subject.augury_name).to eq payload[:order][:payments].first[:payment_method]
        end
      end

      context ".matching_payment" do
        before do
          config["quickbooks_payment_method_name"] = [{ "visa" => "Discover" }]
        end

        it "maps qb_name and store names properly" do
          expect(subject.qb_name).to eq "Discover"
        end

        it "raise when cant find method in quickbooks" do
          subject.quickbooks.stub fetch_by_name: nil

          expect {
            subject.matching_payment
          }.to raise_error
        end

        pending "mock real request with vcr"
      end
    end
  end
end
