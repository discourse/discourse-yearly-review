# frozen_string_literal: true

# name: discourse-yearly-review
# about: Creates an automated Year in Review summary topic
# version: 0.1
# author: Simon Cossar
# url: https://github.com/discourse/discourse-yearly-review

enabled_site_setting :yearly_review_enabled
register_asset "stylesheets/yearly_review.scss"

after_initialize do
  module ::YearlyReview
    PLUGIN_NAME = "yearly-review"

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

  ["../../discourse-yearly-review/app/jobs/yearly_review.rb"].each do |path|
    load File.expand_path(path, __FILE__)
  end

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
end
