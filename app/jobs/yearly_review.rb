require_relative '../../app/helpers/yearly_review_helper'

module ::Jobs
  class YearlyReview < ::Jobs::Scheduled
    MAX_USERS = 10
    MAX_BADGE_USERS = 100

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
      filtered_categories = filter_categories review_categories
      review_featured_badge = SiteSetting.yearly_review_featured_badge
      review_start = Time.new(2018, 1, 1)
      review_end = review_start.end_of_year

      user_stats = user_stats review_categories, review_start, review_end
      category_topics = category_topics filtered_categories, review_start, review_end
      featured_badge_users = review_featured_badge.blank? ? [] : featured_badge_users(review_featured_badge, review_start, review_end)

      view = ActionView::Base.new(ActionController::Base.view_paths,
                                  user_stats: user_stats,
                                  featured_badge_users: featured_badge_users,
                                  category_topics: category_topics)
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

    def filter_categories(category_ids)
      Category.where(id: category_ids).order("topics_year DESC")[0, 7].pluck(:id)
    end

    def user_stats(review_categories, review_start, review_end)
      user_stats = []
      most_time_read = most_time_read review_categories, review_start, review_end
      most_topics = most_topics review_categories, review_start, review_end
      most_replies = most_replies review_categories, review_start, review_end
      most_likes = most_likes_given review_categories, review_start, review_end
      most_likes_received = most_likes_received review_categories, review_start, review_end
      most_visits = most_visits review_start, review_end
      most_replied_to = most_replied_to review_categories, review_start, review_end
      user_stats << { key: 'time_read', users: most_time_read } if most_time_read.any?
      user_stats << { key: 'topics_created', users: most_topics } if most_topics.any?
      user_stats << { key: 'replies_created', users: most_replies } if most_replies.any?
      user_stats << { key: 'likes_given', users: most_likes } if most_likes.any?
      user_stats << { key: 'likes_received', users: most_likes_received } if most_likes_received.any?
      user_stats << { key: 'visits', users: most_visits } if most_visits.any?
      user_stats << { key: 'most_replied_to', users: most_replied_to } if most_replied_to.any?
      user_stats
    end

    def category_topics(category_ids, start_date, end_date)
      topics = {}
      category_ids.each do |cat_id|
        category_topics = {}
        most_read = ranked_topics(cat_id, start_date, end_date, most_read_topic_sql)
        most_liked = ranked_topics(cat_id, start_date, end_date, most_liked_topic_sql)
        most_replied_to = ranked_topics(cat_id, start_date, end_date, most_replied_to_topic_sql)
        most_popular = ranked_topics(cat_id, start_date, end_date, most_popular_topic_sql)
        most_bookmarked = ranked_topics(cat_id, start_date, end_date, most_bookmarked_topic_sql)

        category_topics[:most_read] = most_read if most_read.any?
        category_topics[:most_liked] = most_liked if most_liked.any?
        category_topics[:most_replied_to] = most_replied_to if most_replied_to.any?
        category_topics[:most_popular] = most_popular if most_popular.any?
        category_topics[:most_bookmarked] = most_bookmarked if most_bookmarked.any?
        if category_topics.any?
          category_name = Category.find(cat_id).name
          topics[category_name] = category_topics
        end
      end
      topics
    end

    def ranked_topics(cat_id, start_date, end_date, sql)
      data = []
      DB.query(sql, start_date: start_date, end_date: end_date, cat_id: cat_id, limit: 3).each do |row|
        if row
          action = row.action
          case action
          when 'likes'
            next if row.action_count < 10
          when 'replies'
            next if row.action_count < 10
          when 'bookmarks'
            next if row.action_count < 5
          when 'score'
            next if row.action_count < 10
          when 'read_time'
            next if row.action_count < 1
          end
          data << row
        end
      end
      data
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
        AND p.deleted_at IS NULL
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

    def most_time_read(categories, start_date, end_date)
      sql = <<~SQL
        SELECT
        u.id,
        u.username,
        u.uploaded_avatar_id,
        (SUM(tu.total_msecs_viewed) / (1000 * 60)) AS action_count
        FROM users u
        JOIN topic_users tu
        ON tu.user_id = u.id
        JOIN topics t
        ON t.id = tu.topic_id
        WHERE u.id > 0
        AND t.created_at >= '#{start_date}'
        AND t.created_at <= '#{end_date}'
        AND t.category_id IN (#{categories.join(',')})
        AND t.deleted_at IS NULL
        AND tu.total_msecs_viewed > (1000 * 60)
        GROUP BY u.id, username, uploaded_avatar_id
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
        COUNT(ua.user_id) AS action_count
        FROM user_actions ua
        JOIN topics t
        ON t.id = ua.target_topic_id
        JOIN users u
        ON u.id = ua.user_id
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
        b.id,
        ((COUNT(*) OVER()) - #{MAX_BADGE_USERS}) AS more_users
        FROM badges b
        JOIN user_badges ub
        ON ub.badge_id = b.id
        JOIN users u
        ON u.id = ub.user_id
        WHERE b.name = '#{badge_name}'
        AND ub.granted_at BETWEEN '#{start_date}' AND '#{end_date}'
        AND u.id > 0
        ORDER BY ub.granted_at DESC
        LIMIT #{MAX_BADGE_USERS}
      SQL

      DB.query(sql)
    end

    def most_read_topic_sql
      <<~SQL
      SELECT
      username,
      uploaded_avatar_id,
      t.id,
      t.slug AS topic_slug,
      t.title,
      t.created_at,
      c.slug AS category_slug,
      c.name AS category_name,
      c.id AS category_id,
      ROUND(SUM(tu.total_msecs_viewed::numeric) / (1000 * 60 * 60)::numeric, 2) AS action_count,
      'read_time' AS action
      FROM users u
      JOIN topics t
      ON t.user_id = u.id
      JOIN topic_users tu
      ON tu.topic_id = t.id
      JOIN categories c
      ON c.id = t.category_id
      WHERE t.deleted_at IS NULL
      AND t.created_at BETWEEN :start_date AND :end_date
      AND c.id = :cat_id
      GROUP BY t.id, username, uploaded_avatar_id, c.id
      ORDER BY action_count DESC
      LIMIT :limit
      SQL
    end

    def most_popular_topic_sql
      <<~SQL
        SELECT
        username,
        uploaded_avatar_id,
        t.id,
        t.slug AS topic_slug,
        t.title,
        t.created_at,
        c.slug AS category_slug,
        c.name AS category_name,
        c.id AS category_id,
        ROUND(tt.yearly_score::numeric, 2) AS action_count,
        'score' AS action
        FROM top_topics tt
        JOIN topics t
        ON t.id = tt.topic_id
        JOIN categories c
        ON c.id = t.category_id
        JOIN users u
        ON u.id = t.user_id
        WHERE t.deleted_at IS NULL
        AND t.created_at BETWEEN :start_date AND :end_date
        AND c.id = :cat_id
        ORDER BY tt.yearly_score DESC
        LIMIT :limit
      SQL
    end

    def most_liked_topic_sql
      <<~SQL
        SELECT
        username,
        uploaded_avatar_id,
        t.id,
        t.slug AS topic_slug,
        t.title,
        t.created_at,
        c.slug AS category_slug,
        c.name AS category_name,
        c.id AS category_id,
        COUNT(*) AS action_count,
        'likes' AS action
        FROM post_actions pa
        JOIN posts p
        ON p.id = pa.post_id
        JOIN topics t
        ON t.id = p.topic_id
        JOIN categories c
        ON c.id = t.category_id
        JOIN users u
        ON u.id = t.user_id
        WHERE pa.created_at BETWEEN :start_date AND :end_date
        AND pa.post_action_type_id = 2
        AND c.id = :cat_id
        AND p.post_number = 1
        AND p.deleted_at IS NULL
        AND t.deleted_at IS NULL
        GROUP BY p.id, t.id, topic_slug, category_slug, category_name, c.id, username, uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT :limit
      SQL
    end

    def most_replied_to_topic_sql
      <<~SQL
        SELECT
        username,
        uploaded_avatar_id,
        t.id,
        t.slug AS topic_slug,
        t.title,
        t.created_at,
        c.slug AS category_slug,
        c.name AS category_name,
        c.id AS category_id,
        COUNT(*) AS action_count,
        'replies' AS action
        FROM posts p
        JOIN topics t
        ON t.id = p.topic_id
        JOIN categories c
        ON c.id = t.category_id
        JOIN users u
        ON u.id = t.user_id
        WHERE p.created_at BETWEEN :start_date AND :end_date
        AND c.id = :cat_id
        AND t.deleted_at IS NULL
        AND p.deleted_at IS NULL
        AND p.post_type = 1
        AND t.posts_count > 1
        GROUP BY t.id, topic_slug, category_slug, category_name, c.id, username, uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT :limit
      SQL
    end

    def most_bookmarked_topic_sql
      <<~SQL
        SELECT
        username,
        uploaded_avatar_id,
        t.id,
        t.slug AS topic_slug,
        t.title,
        t.created_at,
        c.slug AS category_slug,
        c.name AS category_name,
        c.id AS category_id,
        COUNT(*) AS action_count,
        'bookmarks' AS action
        FROM post_actions pa
        JOIN posts p
        ON p.id = pa.post_id
        JOIN topics t
        ON t.id = p.topic_id
        JOIN categories c
        ON c.id = t.category_id
        JOIN users u
        ON u.id = t.user_id
        WHERE pa.created_at BETWEEN :start_date AND :end_date
        AND pa.post_action_type_id = 3
        AND c.id = :cat_id
        AND t.deleted_at IS NULL
        AND p.deleted_at IS NULL
        GROUP BY t.id, category_slug, category_name, c.id, username, uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT :limit
      SQL
    end
  end
end
