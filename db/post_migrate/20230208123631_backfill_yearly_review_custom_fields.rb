# frozen_string_literal: true

class BackfillYearlyReviewCustomFields < ActiveRecord::Migration[6.1]
  def change
    2017.upto(2022) do |year|
      topic_title = I18n.t("yearly_review.topic_title", year: review_year)
      DB.exec(
        <<~SQL,
        INSERT INTO post_custom_fields (post_id, name, value, created_at, updated_at)
        SELECT id, :name, :value, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM posts
        INNER JOIN topics ON topics.id = posts.topic_id
        WHERE posts.user_id = :user_id AND topics.title = :title
        ON CONFLICT (post_id, name) DO NOTHING
      SQL
        title: topic_title,
        user_id: Discourse::SYSTEM_USER_ID,
        name: YearlyReview::POST_CUSTOM_FIELD,
        value: year.to_s,
      )
    end
  end
end
