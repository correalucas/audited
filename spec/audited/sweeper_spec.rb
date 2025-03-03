require "spec_helper"

SingleCov.covered! uncovered: 2 # 2 conditional on_load conditions

class AuditsController < ActionController::Base
  before_action :populate_user
  before_action :populate_tenant

  attr_reader :company

  def create
    @company = Models::ActiveRecord::Company.create
    head :ok
  end

  def update
    current_user.update!(password: 'foo')
    head :ok
  end

  private

  attr_accessor :current_user
  attr_accessor :current_tenant
  attr_accessor :custom_user

  def populate_user; end
  def populate_tenant; end
end

describe AuditsController do
  include RSpec::Rails::ControllerExampleGroup
  render_views

  before do
    Audited.current_user_method = :current_user
    Audited.current_tenant_method = :current_tenant
  end

  let(:user) { create_user }
  let(:tenant) { create_tenant }

  describe "POST audit" do
    it "should audit user" do
      controller.send(:current_user=, user)
      controller.send(:current_tenant=, tenant)
      expect {
        post :create
      }.to change( Audited::Audit, :count )

      expect(controller.company.audits.last.user).to eq(user)
    end

    it "does not audit when user method is not found" do
      controller.send(:current_user=, user)
      Audited.current_user_method = :nope_user
      expect {
        post :create
      }.to change( Audited::Audit, :count )
      expect(controller.company.audits.last.user).to eq(nil)
    end

    it "does not audit when tenant method is not found" do
      controller.send(:current_tenant=, tenant)
      Audited.current_tenant_method = :nope_tenant
      expect {
        post :create
      }.to change( Audited::Audit, :count )
      expect(controller.company.audits.last.tenant).to eq(nil)
    end

    it "should support custom users for sweepers" do
      controller.send(:custom_user=, user)
      Audited.current_user_method = :custom_user

      expect {
        post :create
      }.to change( Audited::Audit, :count )

      expect(controller.company.audits.last.user).to eq(user)
    end

    it "should record the remote address responsible for the change" do
      request.env['REMOTE_ADDR'] = "1.2.3.4"
      controller.send(:current_user=, user)

      post :create

      expect(controller.company.audits.last.remote_address).to eq('1.2.3.4')
    end

    it "should record a UUID for the web request responsible for the change" do
      allow_any_instance_of(ActionDispatch::Request).to receive(:uuid).and_return("abc123")
      controller.send(:current_user=, user)
      controller.send(:current_tenant=, tenant)

      post :create

      expect(controller.company.audits.last.request_uuid).to eq("abc123")
    end

    it "should call current_user after controller callbacks" do
      expect(controller).to receive(:populate_user) do
        controller.send(:current_user=, user)
      end

      expect {
        post :create
      }.to change( Audited::Audit, :count )

      expect(controller.company.audits.last.user).to eq(user)
    end

    it "should call current_tenant after controller callbacks" do
      expect(controller).to receive(:populate_tenant) do
        controller.send(:current_tenant=, tenant)
      end

      expect {
        post :create
      }.to change( Audited::Audit, :count )

      expect(controller.company.audits.last.tenant).to eq(tenant)
    end
  end

  describe "PUT update" do
    it "should not save blank audits" do
      controller.send(:current_user=, user)
      controller.send(:current_tenant=, tenant)

      expect {
        put :update, Rails::VERSION::MAJOR == 4 ? {id: 123} : {params: {id: 123}}
      }.to_not change( Audited::Audit, :count )
    end
  end
end

describe Audited::Sweeper do

  it "should be thread-safe" do
    instance = Audited::Sweeper.new

    t1 = Thread.new do
      sleep 0.5
      instance.controller = 'thread1 controller instance'
      expect(instance.controller).to eq('thread1 controller instance')
    end

    t2 = Thread.new do
      instance.controller = 'thread2 controller instance'
      sleep 1
      expect(instance.controller).to eq('thread2 controller instance')
    end

    t1.join; t2.join

    expect(instance.controller).to be_nil
  end

end
