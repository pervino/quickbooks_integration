require "spec_helper"

describe Quickbooks::Online::Client do

  let(:message) {
    {
      "message" => "order:new",
      'message_id' => 'abc',
      :payload => {
        "order" => Factories.order,
        "original" => Factories.original,
        "parameters" => Factories.parameters
      }
    }
  }

  let(:config_param) {config(message) }
  let(:client) { Quickbooks::Base.client(message[:payload], "abc", config_param, message["message"]) }


  context "#find_account_by_name" do

    it "will return a Quickeebooks::Online::Model::Account instance" do
      VCR.use_cassette('online/account_name_found') do
        account = client.find_account_by_name("Sales")
        account.class.should eql Quickeebooks::Online::Model::Account
        account.id.class.should eql Quickeebooks::Online::Model::Id
        account.id.value.should eql "1"
        account.name.should eql "Sales"
      end
    end

    it "will raise an exception when the account name is not found" do
      VCR.use_cassette('online/account_name_not_found') do
        expect {
          client.find_account_by_name("Blaat")
          }.to raise_error(Exception, "No Account 'Blaat' defined in Quickbooks")
      end
    end
  end

  context "#find_payment_by_name" do

    it "will return a Quickeebooks::Online::Model::PaymentMethod instance" do
      VCR.use_cassette('online/payment_method_found') do
        payment_method = client.find_payment_method_by_name("Visa")
        payment_method.class.should eql Quickeebooks::Online::Model::PaymentMethod
        payment_method.id.class.should eql Quickeebooks::Online::Model::Id
        payment_method.id.value.should eql "3"
        payment_method.name.should eql "Visa"
      end
    end

    it "will raise an exception when the account name is not found" do
      VCR.use_cassette('online/payment_method_not_found_found') do
        expect {
          client.find_payment_method_by_name("Blaat")
          }.to raise_error(Exception, "No PaymentMethod 'Blaat' defined in Quickbooks")
      end
    end
  end

  context "#find_item_by_sku" do
    it "will return nil if no item was found" do
      VCR.use_cassette('online/find_item_by_sku_with_no_result') do
        client.find_item_by_sku("blaat").should be_nil
      end
    end

    it "will return a Quickeebooks::Online::Model::Item instance" do
      VCR.use_cassette('online/find_item_by_sku') do
        item = client.find_item_by_sku("Hours")
        item.should_not be_nil
        item.name.should eql "Hours"
        item.class.should eql Quickeebooks::Online::Model::Item
      end
    end
  end

  context "#create_item" do

    it "will add an item to Quickbooks" do
      VCR.use_cassette('online/create_item') do
        sku = "test123"
        desc = "Decriptiopn"
        price = 14.99
        item = client.create_item(sku,desc,price)
        item.id.should_not be_nil
        item.class.should eql Quickeebooks::Online::Model::Item
        item.unit_price.amount.should eql 14.99
      end
    end

    context "with a sku that already exists" do
      it "will return the item with matching sku" do
        VCR.use_cassette('online/create_item_twice') do
          sku = "test-abc"
          desc = "a nice test item"
          price = 14.99
          item = client.create_item(sku,desc,price)
          item.id.should_not be_nil
          item.class.should eql Quickeebooks::Online::Model::Item
          item.unit_price.amount.should eql 14.99
          item2 = client.create_item(sku,desc,19.99)
          item2.id.should_not be_nil
          item2.id.value.should eql item.id.value
          item2.unit_price.amount.should eql 14.99
        end
      end
    end
  end

  context "#find_customer_by_name" do

    it "will return nil if no customer was found" do
      VCR.use_cassette('online/find_customer_by_name_with_no_result') do
        client.find_customer_by_name("Harry Hare").should be_nil
      end
    end

    it "will return a Quickeebooks::Online::Model::Customer instance" do
      VCR.use_cassette('online/find_customer_by_name') do
        customer = client.find_customer_by_name("John Do")
        customer.should_not be_nil
        customer.class.should eql Quickeebooks::Online::Model::Customer
      end
    end
  end

  context "#create_customer" do
    it "will add a customer to Quickbooks" do
      VCR.use_cassette('online/create_customer') do
        customer = client.create_customer
        customer.should_not be_nil
        customer.class.should eql Quickeebooks::Online::Model::Customer
        customer.name.should eql "Brian Quinn"

        customer.billing_address.should_not be_nil
        customer.billing_address.class.should eql Quickeebooks::Online::Model::Address

        customer.shipping_address.should_not be_nil
        customer.shipping_address.class.should eql Quickeebooks::Online::Model::Address

      end
    end

    it "will raise an exception if the name is already in use" do

      VCR.use_cassette('online/create_customer_with_same_name') do
        customer = client.create_customer
        customer.should_not be_nil
        customer.class.should eql Quickeebooks::Online::Model::Customer
        expect {
          client.create_customer
        }.to raise_error(IntuitRequestException)
      end
    end
  end

  context "#sales_receipt" do
    it "creates the sales_receipt" do
      VCR.use_cassette("online/create_sales_receipt") do
        receipt = client.sales_receipt
        receipt.should_not be_nil
        receipt.line_items.count.should eql 5
        receipt.doc_number.should eql "R181807170"
      end
    end
  end

  context "#persit" do

    context "for a new order" do

      it "creates a new sales receipt for a new order" do
        CrossReference.any_instance.stub(:lookup).with("R181807170").and_return(nil)
        VCR.use_cassette('online/persist_new_order') do
          response_hash = {:id=>"45", :id_domain=>"QBO"}
          client.persist["xref"].should eql response_hash
        end
      end
    end

    context "for an updated order" do

      let(:message) {
        {
          "message" => "order:updated",
          'message_id' => 'abc',
          :payload => {
            "order" => Factories.order(Factories.order_changes),
            "original" => Factories.original,
            "parameters" => Factories.parameters
          }
        }
      }

      let(:client) { Quickbooks::Base.client(message[:payload], "abc", config_param, message["message"]) }

      it "updates the existing sales receipt" do
        VCR.use_cassette('online/persist_updated_order') do
          result = client.persist
          receipt = result["receipt"]
          receipt.header.total_amount.should eql 134.94
        end
      end
    end
  end

end