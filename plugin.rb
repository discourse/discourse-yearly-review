# name: discourse-yearly-review
# about: creates a yearly review post
# version: 0.1
# Authors Simon Cossar

enabled_site_setting :yearly_review_enabled
PLUGIN_NAME = 'yearly-review'.freeze

after_initialize do
  ::ActionController::Base.prepend_view_path File.expand_path("../app/views/yearly-review", __FILE__)

  [
    '../../discourse-yearly-review/app/jobs/yearly_review.rb'
  ].each { |path| load File.expand_path(path, __FILE__) }

end

register_css <<CSS
[data-review-topic="true"] table {
    width: 100%;
}
[data-review-topic="true"] table th {
    text-align: left;
    width: 50%;
}
[data-review-users="true"] span {
    white-space: pre;
    display: inline-block;
    margin-bottom: 4px;
}
CSS
