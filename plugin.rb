# frozen_string_literal: true

# name: discourse-yearly-review
# about: Creates a topic that summarizes the previous year’s forum activity.
# meta_topic_id: 105713
# version: 0.2
# author: Simon Cossar
# url: https://github.com/discourse/discourse-yearly-review

enabled_site_setting :yearly_review_enabled
register_asset "stylesheets/yearly_review.scss"

after_initialize do
  module ::YearlyReview
    PLUGIN_NAME = "yearly-review"
    POST_CUSTOM_FIELD = "yearly_review"

    def self.current_year
      Time.now.year
    end

    def self.last_year
      current_year - 1
    end
  end

  ::ActionController::Base.prepend_view_path File.expand_path(
                                               "../app/views/yearly-review",
                                               __FILE__,
                                             )

  require_relative "app/jobs/yearly_review"

  require_dependency "email/styles"
  Email::Styles.register_plugin_style do |doc|
    doc.css("[data-review-topic-users] table").each { |element| element["width"] = "100%" }
    doc.css("[data-review-featured-topics] table").each { |element| element["width"] = "100%" }

    doc
      .css("[data-review-topic-users] th")
      .each do |element|
        element["style"] = "text-align: left;padding-bottom: 12px;"
        element["width"] = "50%"
      end
    doc
      .css("[data-review-featured-topics] th")
      .each { |element| element["style"] = "text-align: left;padding-bottom: 12px;" }
    doc
      .css("[data-review-featured-topics] th:first-child")
      .each { |element| element["width"] = "15%" }
    doc
      .css("[data-review-featured-topics] th:nth-child(2)")
      .each { |element| element["width"] = "60%" }
    doc
      .css("[data-review-featured-topics] th:last-child")
      .each { |element| element["width"] = "25%" }

    doc
      .css("[data-review-topic-users] td")
      .each do |element|
        element["style"] = "padding-bottom: 6px;"
        element["valign"] = "top"
      end
    doc
      .css("[data-review-featured-topics] td")
      .each do |element|
        element["style"] = "padding-bottom: 6px;"
        element["valign"] = "top"
      end

    doc
      .css("[data-review-topic-users] td table td:first-child")
      .each do |element|
        element["style"] = "padding-bottom: 6px;"
        element["width"] = "25"
      end
    doc
      .css("[data-review-topic-users] td table td:nth-child(2)")
      .each { |element| element["style"] = "padding-left: 4px;padding-bottom: 6px;" }
  end

  on(:username_changed) do |old_username, new_username|
    Post
      .joins(:_custom_fields)
      .where(
        "post_custom_fields.name = ? AND posts.raw LIKE ?",
        YearlyReview::POST_CUSTOM_FIELD,
        "%/#{old_username}/%",
      )
      .update_all(
        "raw = REPLACE(raw, '/#{old_username}/', '/#{new_username}/'), baked_version = NULL",
      )
  end
end
