# name: discourse-yearly-review
# about: Creates an automated Year in Review summary topic
# version: 0.1
# author: Simon Cossar
# url: https://github.com/discourse/discourse-yearly-review

enabled_site_setting :yearly_review_enabled
register_asset 'stylesheets/yearly_review.scss'

PLUGIN_NAME = 'yearly-review'.freeze

after_initialize do
  ::ActionController::Base.prepend_view_path File.expand_path("../app/views/yearly-review", __FILE__)

  [
    '../../discourse-yearly-review/app/jobs/yearly_review.rb'
  ].each { |path| load File.expand_path(path, __FILE__) }

end
