require_relative '../../app/helpers/yearly_review_helper'

module ::Jobs
  class YearlyReview < ::Jobs::Scheduled
    MAX_USERS = 15
    MAX_POSTS_PER_CATEGORY = 3

    every 1.day
    def execute(args)
      now = Time.now
      title = I18n.t("yearly_review.topic_title", year: now.year - 1)

      unless args[:force]
        return unless SiteSetting.yearly_review_enabled
        return unless now.month == 1 && now.day < 8
        return if Topic.where(user: Discourse.system_user, title: title).exists?
      end

      raw = create_raw_topic

      opts = {
        title: title,
        raw: raw,
        category: SiteSetting.yearly_review_publish_category,
        skip_validations: true
      }

      PostCreator.create!(Discourse.system_user, opts)
    end

    def create_raw_topic
      review_categories = review_categories_from_settings
      review_featured_badge = SiteSetting.yearly_review_featured_badge
      review_start = Time.new(2018, 1, 1)
      review_end = review_start.end_of_year

      most_topics = most_topics review_categories, review_start, review_end
      most_replies = most_replies review_categories, review_start, review_end
      most_likes = most_likes_given review_categories, review_start, review_end
      most_likes_received = most_likes_received review_categories, review_start, review_end
      most_visits = most_visits review_start, review_end
      most_replied_to = most_replied_to review_categories, review_start, review_end
      most_popular_topics = most_popular_topics review_categories, review_start, review_end
      most_liked_topics = most_liked_topics review_categories, review_start, review_end
      most_replied_to_topics = most_replied_to_topics review_categories, review_start, review_end
      most_bookmarked_topics = most_bookmarked_topics review_categories, review_start, review_end
      featured_badge_users = review_featured_badge.blank? ? [] : featured_badge_users(review_featured_badge, review_start, review_end)

      user_stats = []
      user_stats << { key: 'topics_created', users: most_topics } if most_topics.any?
      user_stats << { key: 'replies_created', users: most_replies } if most_replies.any?
      user_stats << { key: 'likes_given', users: most_likes } if most_likes.any?
      user_stats << { key: 'likes_received', users: most_likes_received } if most_likes_received.any?
      user_stats << { key: 'visits', users: most_visits } if most_visits.any?
      user_stats << { key: 'most_replied_to', users: most_replied_to } if most_replied_to.any?

      view = ActionView::Base.new(ActionController::Base.view_paths,
                                  user_stats: user_stats,
                                  most_popular_topics: most_popular_topics,
                                  most_liked_topics: most_liked_topics,
                                  most_replied_to_topics: most_replied_to_topics,
                                  most_bookmarked_topics: most_bookmarked_topics,
                                  featured_badge_users: featured_badge_users)
      view.class_eval do
        include YearlyReviewHelper
      end

      view.render template: "yearly_review", formats: :html, layout: false
    end

    def review_categories_from_settings
      if SiteSetting.yearly_review_categories.blank?
        Category.where(read_restricted: false).pluck(:id)
      else
        Category.where(read_restricted: false, id: SiteSetting.yearly_review_categories.split('|')).pluck(:id)
      end
    end

    def most_topics(categories, start_date, end_date)
      sql = <<~SQL
        SELECT
        t.user_id,
        COUNT(t.user_id) AS action_count,
        u.username,
        u.uploaded_avatar_id
        FROM topics t
        JOIN users u
        ON u.id = t.user_id
        WHERE t.archetype = 'regular'
        AND t.user_id > 0
        AND t.created_at >= '#{start_date}'
        AND t.created_at <= '#{end_date}'
        AND t.category_id IN (#{categories.join(',')})
        AND t.deleted_at IS NULL
        GROUP BY t.user_id, u.username, u.uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT #{MAX_USERS}
      SQL

      DB.query(sql)
    end

    def most_replies(categories, start_date, end_date)
      sql = <<~SQL
        SELECT
        p.user_id,
        u.username,
        u.uploaded_avatar_id,
        COUNT(p.user_id) AS action_count
        FROM posts p
        JOIN users u
        ON u.id = p.user_id
        JOIN topics t
        ON t.id = p.topic_id
        WHERE t.archetype = 'regular'
        AND p.user_id > 0
        AND p.post_number > 1
        AND p.post_type = 1
        AND p.created_at >= '#{start_date}'
        AND p.created_at <= '#{end_date}'
        AND t.category_id IN (#{categories.join(',')})
        AND t.deleted_at IS NULL
        GROUP BY p.user_id, u.username, u.uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT #{MAX_USERS}
      SQL

      DB.query(sql)
    end

    def most_visits(start_date, end_date)
      sql = <<~SQL
        SELECT
        uv.user_id,
        u.username,
        u.uploaded_avatar_id,
        COUNT(uv.user_id) AS action_count
        FROM user_visits uv
        JOIN users u
        ON u.id = uv.user_id
        WHERE u.id > 0
        AND uv.visited_at >= '#{start_date}'
        AND uv.visited_at <= '#{end_date}'
        GROUP BY uv.user_id, u.username, u.uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT #{MAX_USERS}
      SQL

      DB.query(sql)
    end

    def most_likes_given(categories, start_date, end_date)
      sql = <<~SQL
        SELECT
        ua.acting_user_id,
        u.username,
        u.uploaded_avatar_id,
        COUNT(ua.user_id) AS action_count
        FROM user_actions ua
        JOIN topics t
        ON t.id = ua.target_topic_id
        JOIN users u
        ON u.id = ua.acting_user_id
        WHERE u.id > 0
        AND ua.created_at >= '#{start_date}'
        AND ua.created_at <= '#{end_date}'
        AND ua.action_type = 2
        AND t.category_id IN (#{categories.join(',')})
        AND t.deleted_at IS NULL
        GROUP BY ua.acting_user_id, u.username, u.uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT #{MAX_USERS}
      SQL

      DB.query(sql)
    end

    def most_likes_received(categories, start_date, end_date)
      sql = <<~SQL
        SELECT
        u.username,
        u.uploaded_avatar_id,
        COUNT(p.user_id) AS action_count
        FROM user_actions ua
        JOIN topics t
        ON t.id = ua.target_topic_id
        JOIN posts p
        ON p.id = ua.target_post_id
        JOIN users u
        ON u.id = p.user_id
        WHERE u.id > 0
        AND ua.created_at >= '#{start_date}'
        AND ua.created_at <= '#{end_date}'
        AND ua.action_type = 2
        AND t.category_id IN (#{categories.join(',')})
        AND t.deleted_at IS NULL
        GROUP BY u.username, u.uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT #{MAX_USERS}
      SQL

      DB.query(sql)
    end

    def most_replied_to(categories, start_date, end_date)
      sql = <<~SQL
        SELECT
        u.username,
        u.uploaded_avatar_id,
        SUM(p.reply_count) AS action_count
        FROM posts p
        JOIN topics t
        ON t.id = p.topic_id
        JOIN users u
        ON u.id = p.user_id
        WHERE p.created_at >= '#{start_date}'
        AND p.created_at <= '#{end_date}'
        AND p.reply_count > 0
        AND t.category_id IN (#{categories.join(',')})
        AND t.deleted_at IS NULL
        AND p.deleted_at IS NULL
        AND p.post_type = 1
        AND p.user_id > 0
        GROUP BY u.username, u.uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT #{MAX_USERS}
      SQL

      DB.query(sql)
    end

    def featured_badge_users(badge_name, start_date, end_date)
      sql = <<~SQL
        SELECT
        u.id AS user_id,
        username,
        uploaded_avatar_id,
        b.name,
        b.icon,
        b.image,
        b.id
        FROM badges b
        JOIN user_badges ub
        ON ub.badge_id = b.id
        JOIN users u
        ON u.id = ub.user_id
        WHERE b.name = '#{badge_name}'
        AND ub.granted_at BETWEEN '#{start_date}' AND '#{end_date}'
        AND u.id > 0
      SQL

      DB.query(sql)
    end

    def most_popular_topic_sql
      <<~SQL
        SELECT
        t.id,
        t.slug AS topic_slug,
        t.title,
        c.slug AS category_slug,
        c.name AS category_name,
        c.id as category_id,
        tt.yearly_score
        FROM top_topics tt
        JOIN topics t
        ON t.id = tt.topic_id
        JOIN categories c
        ON c.id = t.category_id
        WHERE t.deleted_at IS NULL
        AND c.id = :cat_id
        ORDER BY tt.yearly_score DESC
        LIMIT #{MAX_POSTS_PER_CATEGORY}
      SQL
    end

    def most_liked_topic_sql
      <<~SQL
        SELECT
        t.id,
        t.slug AS topic_slug,
        t.title,
        c.slug AS category_slug,
        c.name AS category_name,
        c.id AS category_id,
        COUNT(*) AS action_count
        FROM post_actions pa
        JOIN posts p
        ON p.id = pa.post_id
        JOIN topics t
        ON t.id = p.topic_id
        JOIN categories c
        ON c.id = t.category_id
        WHERE pa.created_at BETWEEN :start_date AND :end_date
        AND pa.post_action_type_id = 2
        AND c.id = :cat_id
        AND p.post_number = 1
        AND p.deleted_at IS NULL
        AND t.deleted_at IS NULL
        GROUP BY p.id, t.id, topic_slug, category_slug, category_name, c.id
        ORDER BY action_count DESC
        LIMIT #{MAX_POSTS_PER_CATEGORY}
      SQL
    end

    def most_replied_to_topic_sql
      <<~SQL
        SELECT
        t.id,
        t.slug AS topic_slug,
        t.title,
        c.slug AS category_slug,
        c.name AS category_name,
        c.id AS category_id,
        COUNT(*) AS action_count
        FROM posts p
        JOIN topics t
        ON t.id = p.topic_id
        JOIN categories c
        ON c.id = t.category_id
        WHERE p.created_at BETWEEN :start_date AND :end_date
        AND c.id = :cat_id
        AND t.deleted_at IS NULL
        AND p.deleted_at IS NULL
        AND p.post_type = 1
        AND t.posts_count > 1
        GROUP BY t.id, topic_slug, category_slug, category_name, c.id
        ORDER BY action_count DESC
        LIMIT #{MAX_POSTS_PER_CATEGORY}
      SQL
    end

    def most_bookmarked_topic_sql
      <<~SQL
        SELECT
        t.id,
        t.slug AS topic_slug,
        t.title,
        c.slug AS category_slug,
        c.name AS category_name,
        c.id AS category_id,
        COUNT(*) AS action_count
        FROM post_actions pa
        JOIN posts p
        ON p.id = pa.post_id
        JOIN topics t
        ON t.id = p.topic_id
        JOIN categories c
        ON c.id = t.category_id
        WHERE pa.created_at BETWEEN :start_date AND :end_date
        AND pa.post_action_type_id = 3
        AND c.id = :cat_id
        AND t.deleted_at IS NULL
        AND p.deleted_at IS NULL
        GROUP BY t.id, category_slug, category_name, c.id
        ORDER BY action_count DESC
        LIMIT #{MAX_POSTS_PER_CATEGORY}
      SQL
    end

    def most_liked_topics(cat_ids, start_date, end_date)
      category_topics(start_date, end_date, cat_ids, most_liked_topic_sql)
    end

    def most_replied_to_topics(cat_ids, start_date, end_date)
      category_topics(start_date, end_date, cat_ids, most_replied_to_topic_sql)
    end

    def most_popular_topics(cat_ids, start_date, end_date)
      category_topics(start_date, end_date, cat_ids, most_popular_topic_sql)
    end

    def most_bookmarked_topics(cat_ids, start_date, end_date)
      category_topics(start_date, end_date, cat_ids, most_bookmarked_topic_sql)
    end

    def category_topics(start_date, end_date, category_ids, sql)
      data = []
      category_ids.each do |cat_id|
        DB.query(sql, start_date: start_date, end_date: end_date, cat_id: cat_id).each_with_index do |row, i|
          if row
            title = category_link_title(row.category_slug, row.category_id, row.category_name)
            data << "<h3>#{title}</h3>" if i == 0
            data << topic_link(row.topic_slug, row.id)
          end
        end
      end
      data
    end

    def topic_link(slug, topic_id)
      url = " #{Discourse.base_url}/t/#{slug}/#{topic_id}"
      url.strip
    end

    def category_link_title(slug, id, name)
      "<a class='hashtag' href='/c/#{slug}/#{id}'>##{name}</a>"
    end
  end
end
