# name: discourse-yearly-review
# about: creates a yearly review post
# version: 0.1
# Authors Simon Cossar

enabled_site_setting :yearly_review_enabled
PLUGIN_NAME = 'yearly-review'.freeze
add_admin_route 'yearly_review.title', 'yearly-review'

after_initialize do
  SeedFu.fixture_paths << Rails.root.join("plugins", "discourse-yearly-review", "db", "fixtures").to_s

  require_dependency 'admin_constraint'
  # Look at how this is done in the site_report plugin
  ::ActionController::Base.prepend_view_path File.expand_path("../app/views/yearly-review", __FILE__)

  module ::YearlyReview
    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace YearlyReview
    end
  end

  [
    '../../discourse-yearly-review/app/jobs/yearly_review.rb'
  ].each { |path| load File.expand_path(path, __FILE__) }

  require_dependency 'admin/admin_controller'
  class YearlyReview::YearlyReviewController < ::Admin::AdminController
    def create
      Jobs::YearlyReview.new.execute
    end
  end

  YearlyReview::Engine.routes.draw do
    root to: "yearly_review#index", constraints: AdminConstraint.new
    post 'create', to: 'yearly_review#create', constraints: AdminConstraint.new
  end

  Discourse::Application.routes.append do
    mount ::YearlyReview::Engine, at: '/admin/plugins/yearly-review', constraints: AdminConstraint.new
  end
end
