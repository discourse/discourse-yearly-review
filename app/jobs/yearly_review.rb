# frozen_string_literal: true

require_relative "../../app/helpers/yearly_review_helper"

module ::Jobs
  class YearlyReview < ::Jobs::Scheduled
    MAX_USERS = 10
    MAX_BADGE_USERS = 15

    every 1.day

    def execute(args)
      now = Time.now
      review_year = args[:review_year] ? args[:review_year] : ::YearlyReview.last_year
      review_start = Time.new(review_year, 1, 1)
      review_end = review_start.end_of_year
      title = I18n.t("yearly_review.topic_title", year: review_year)

      if !args[:force]
        return if !SiteSetting.yearly_review_enabled
        return unless now.month == 1 && now.day <= 31
        return if review_topic_exists?(review_year)
      end

      view = ActionView::Base.with_view_paths(ActionController::Base.view_paths)
      view.class_eval do
        include YearlyReviewHelper
        def compiled_method_container
          self.class
        end
      end

      raw_topic_html = render_raw_topic_view(view, review_year, review_start, review_end)
      if raw_topic_html.present?
        topic_opts = {
          title: title,
          raw: raw_topic_html,
          category: SiteSetting.yearly_review_publish_category,
          skip_validations: true,
          custom_fields: {
            ::YearlyReview::POST_CUSTOM_FIELD => review_year,
          },
        }

        post = PostCreator.create!(Discourse.system_user, topic_opts)

        if post.respond_to? :topic_id
          create_category_posts view, review_start, review_end, post.topic_id
        end
      end
    end

    def render_raw_topic_view(view, review_year, review_start, review_end)
      review_featured_badge = SiteSetting.yearly_review_featured_badge
      include_user_stats = SiteSetting.yearly_review_include_user_stats

      user_stats = include_user_stats ? user_stats(review_start, review_end) : []
      featured_badge_users =
        (
          if review_featured_badge.blank?
            []
          else
            featured_badge_users(review_featured_badge, review_start, review_end)
          end
        )
      daily_visits = daily_visits review_start, review_end
      view.assign(
        review_year: review_year,
        user_stats: user_stats,
        daily_visits: daily_visits,
        featured_badge_users: featured_badge_users,
      )

      view.render partial: "yearly_review", layout: false
    end

    def create_category_posts(view, review_start, review_end, topic_id)
      review_categories = review_categories_from_settings

      review_categories.each do |category_id|
        category_post_topics = category_post_topics category_id, review_start, review_end
        if category_post_topics[:topics]
          view.assign(category_topics: category_post_topics)
          raw_html = view.render partial: "yearly_review_category", layout: false
          if raw_html.present?
            post_opts = {
              topic_id: topic_id,
              raw: raw_html,
              skip_validations: true,
              custom_fields: {
                ::YearlyReview::POST_CUSTOM_FIELD => review_start.year,
              },
            }

            PostCreator.create!(Discourse.system_user, post_opts)
          end
        end
      end
    end

    def category_post_topics(cat_id, start_date, end_date)
      data = {}

      most_read = ranked_topics(cat_id, start_date, end_date, most_read_topic_sql)
      most_liked = ranked_topics(cat_id, start_date, end_date, most_liked_topic_sql)
      most_replied_to = ranked_topics(cat_id, start_date, end_date, most_replied_to_topic_sql)
      most_popular = ranked_topics(cat_id, start_date, end_date, most_popular_topic_sql)
      most_bookmarked = ranked_topics(cat_id, start_date, end_date, most_bookmarked_topic_sql)

      category_topics = {}
      category_topics[:most_read] = most_read if most_read.any?
      category_topics[:most_liked] = most_liked if most_liked.any?
      category_topics[:most_replied_to] = most_replied_to if most_replied_to.any?
      category_topics[:most_popular] = most_popular if most_popular.any?
      category_topics[:most_bookmarked] = most_bookmarked if most_bookmarked.any?

      if category_topics.any?
        category_name = Category.find(cat_id).name
        data[:category_name] = category_name
        data[:topics] = category_topics
      end

      data
    end

    def review_categories_from_settings
      read_restricted = SiteSetting.yearly_review_include_private_categories

      if SiteSetting.yearly_review_categories.blank?
        Category.where(read_restricted: false).order("topics_year DESC")[0, 5].pluck(:id)
      else
        opts = {}
        opts[:read_restricted] = false if read_restricted == false
        opts[:id] = SiteSetting.yearly_review_categories.split("|")
        Category.where(opts).order("topics_year DESC").pluck(:id)
      end
    end

    def user_stats(review_start, review_end)
      exclude_staff = SiteSetting.yearly_review_exclude_staff
      read_restricted = SiteSetting.yearly_review_include_private_categories
      user_stats = []
      most_time_read = most_time_read review_start, review_end, exclude_staff, read_restricted
      most_topics = most_topics review_start, review_end, exclude_staff, read_restricted
      most_replies = most_replies review_start, review_end, exclude_staff, read_restricted
      most_likes = most_likes_given review_start, review_end, exclude_staff, read_restricted
      most_likes_received =
        most_likes_received review_start, review_end, exclude_staff, read_restricted
      most_visits = most_visits review_start, review_end, exclude_staff
      most_replied_to = most_replied_to review_start, review_end, exclude_staff, read_restricted
      user_stats << { key: "time_read", users: most_time_read } if most_time_read.any?
      user_stats << { key: "topics_created", users: most_topics } if most_topics.any?
      user_stats << { key: "replies_created", users: most_replies } if most_replies.any?
      user_stats << { key: "most_replied_to", users: most_replied_to } if most_replied_to.any?
      user_stats << { key: "likes_given", users: most_likes } if most_likes.any?
      if most_likes_received.any?
        user_stats << { key: "likes_received", users: most_likes_received }
      end
      user_stats << { key: "visits", users: most_visits } if most_visits.any?
      user_stats
    end

    def ranked_topics(cat_id, start_date, end_date, sql)
      data = []
      exclude_staff = SiteSetting.yearly_review_exclude_staff
      DB
        .query(
          sql,
          start_date: start_date,
          end_date: end_date,
          cat_id: cat_id,
          exclude_staff: exclude_staff,
          limit: 5,
        )
        .each do |row|
          if row
            action = row.action
            case action
            when "likes"
              next if row.action_count < 10
            when "replies"
              next if row.action_count < 10
            when "bookmarks"
              next if row.action_count < 5
            when "score"
              next if row.action_count < 10
            when "read_time"
              next if row.action_count < 5
            end
            data << row
          end
        end
      data
    end

    def most_topics(start_date, end_date, exclude_staff, read_restricted)
      sql = <<~SQL
        SELECT
        t.user_id,
        COUNT(t.user_id) AS action_count,
        u.username,
        u.uploaded_avatar_id
        FROM topics t
        JOIN users u
        ON u.id = t.user_id
        JOIN categories c
        ON c.id = t.category_id
        WHERE t.archetype = 'regular'
        AND ((#{!exclude_staff}) OR (u.admin = false AND u.moderator = false))
        #{"AND c.read_restricted = false" unless read_restricted}
        AND t.user_id > 0
        AND t.created_at >= '#{start_date}'
        AND t.created_at <= '#{end_date}'
        AND t.deleted_at IS NULL
        GROUP BY t.user_id, u.username, u.uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT #{MAX_USERS}
      SQL

      DB.query(sql)
    end

    def most_replies(start_date, end_date, exclude_staff, read_restricted)
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
        JOIN categories c
        ON c.id = t.category_id
        WHERE t.archetype = 'regular'
        AND ((#{!exclude_staff}) OR (u.admin = false AND u.moderator = false))
        #{"AND c.read_restricted = false" unless read_restricted}
        AND p.user_id > 0
        AND p.post_number > 1
        AND p.post_type = 1
        AND p.created_at >= '#{start_date}'
        AND p.created_at <= '#{end_date}'
        AND t.deleted_at IS NULL
        AND p.deleted_at IS NULL
        GROUP BY p.user_id, u.username, u.uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT #{MAX_USERS}
      SQL

      DB.query(sql)
    end

    def daily_visits(start_date, end_date)
      sql = <<~SQL
      WITH visits AS (
      SELECT
      user_id,
      COUNT(user_id) AS days_visited_count
      FROM user_visits uv
      WHERE uv.visited_at >= '#{start_date}'
      AND uv.visited_at <= '#{end_date}'
      GROUP BY user_id
      )
      SELECT
      COUNT(user_id) AS users,
      days_visited_count AS days
      FROM visits
      GROUP BY days_visited_count
      ORDER BY days_visited_count DESC
      LIMIT 10
      SQL

      DB.query(sql)
    end

    def most_visits(start_date, end_date, exclude_staff)
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
        AND ((#{!exclude_staff}) OR (u.admin = false AND u.moderator = false))
        AND uv.visited_at >= '#{start_date}'
        AND uv.visited_at <= '#{end_date}'
        GROUP BY uv.user_id, u.username, u.uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT #{MAX_USERS}
      SQL

      DB.query(sql)
    end

    def most_time_read(start_date, end_date, exclude_staff, read_restricted)
      sql = <<~SQL
        SELECT
        u.id,
        u.username,
        u.uploaded_avatar_id,
        ROUND(SUM(tu.total_msecs_viewed::numeric) / (1000 * 60 * 60)::numeric, 2) AS action_count
        FROM users u
        JOIN topic_users tu
        ON tu.user_id = u.id
        JOIN topics t
        ON t.id = tu.topic_id
        JOIN categories c
        ON c.id = t.category_id
        WHERE t.archetype = 'regular'
        AND ((#{!exclude_staff}) OR (u.admin = false AND u.moderator = false))
        #{"AND c.read_restricted = false" unless read_restricted}
        AND u.id > 0
        AND t.created_at >= '#{start_date}'
        AND t.created_at <= '#{end_date}'
        AND t.deleted_at IS NULL
        AND tu.total_msecs_viewed > (1000 * 60)
        GROUP BY u.id, username, uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT #{MAX_USERS}
      SQL

      DB.query(sql)
    end

    def most_likes_given(start_date, end_date, exclude_staff, read_restricted)
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
        JOIN categories c
        ON c.id = t.category_id
        WHERE t.archetype = 'regular'
        AND ((#{!exclude_staff}) OR (u.admin = false AND u.moderator = false))
        #{"AND c.read_restricted = false" unless read_restricted}
        AND u.id > 0
        AND ua.created_at >= '#{start_date}'
        AND ua.created_at <= '#{end_date}'
        AND ua.action_type = 2
        AND t.deleted_at IS NULL
        GROUP BY ua.acting_user_id, u.username, u.uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT #{MAX_USERS}
      SQL

      DB.query(sql)
    end

    def most_likes_received(start_date, end_date, exclude_staff, read_restricted)
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
        JOIN categories c
        ON c.id = t.category_id
        WHERE t.archetype = 'regular'
        AND ((#{!exclude_staff}) OR (u.admin = false AND u.moderator = false))
        #{"AND c.read_restricted = false" unless read_restricted}
        AND u.id > 0
        AND ua.created_at >= '#{start_date}'
        AND ua.created_at <= '#{end_date}'
        AND ua.action_type = 2
        AND t.deleted_at IS NULL
        GROUP BY u.username, u.uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT #{MAX_USERS}
      SQL

      DB.query(sql)
    end

    def most_replied_to(start_date, end_date, exclude_staff, read_restricted)
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
        JOIN categories c
        ON c.id = t.category_id
        WHERE t.archetype = 'regular'
        AND ((#{!exclude_staff}) OR (u.admin = false AND u.moderator = false))
        #{"AND c.read_restricted = false" unless read_restricted}
        AND p.created_at >= '#{start_date}'
        AND p.created_at <= '#{end_date}'
        AND p.reply_count > 0
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
      exclude_staff = SiteSetting.yearly_review_exclude_staff
      sql = <<~SQL
        SELECT DISTINCT ON(u.id)
        u.id AS user_id,
        username,
        uploaded_avatar_id,
        b.name,
        b.id,
        ((COUNT(*) OVER()) - #{MAX_BADGE_USERS}) AS more_users
        FROM badges b
        JOIN user_badges ub
        ON ub.badge_id = b.id
        JOIN users u
        ON u.id = ub.user_id
        WHERE b.name = '#{badge_name}'
        AND ((#{!exclude_staff}) OR (u.admin = false AND u.moderator = false))
        AND ub.granted_at BETWEEN '#{start_date}' AND '#{end_date}'
        AND u.id > 0
        ORDER BY u.id
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
        AND ((:exclude_staff = false) OR (u.admin = false AND u.moderator = false))
        AND t.created_at BETWEEN :start_date AND :end_date
        AND t.visible = true
        AND c.id = :cat_id
        AND u.id > 0
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
        AND ((:exclude_staff = false) OR (u.admin = false AND u.moderator = false))
        AND t.created_at BETWEEN :start_date AND :end_date
        AND t.visible = true
        AND c.id = :cat_id
        AND u.id > 0
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
        AND ((:exclude_staff = false) OR (u.admin = false AND u.moderator = false))
        AND pa.post_action_type_id = 2
        AND c.id = :cat_id
        AND p.post_number = 1
        AND p.deleted_at IS NULL
        AND t.deleted_at IS NULL
        AND t.visible = true
        AND u.id > 0
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
        AND ((:exclude_staff = false) OR (u.admin = false AND u.moderator = false))
        AND c.id = :cat_id
        AND t.deleted_at IS NULL
        AND t.visible = true
        AND p.deleted_at IS NULL
        AND p.post_type = 1
        AND p.post_number > 1
        AND t.posts_count > 1
        AND u.id > 0
        GROUP BY t.id, topic_slug, category_slug, category_name, c.id, username, uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT :limit
      SQL
    end

    def most_bookmarked_topic_sql
      post_bookmark_join_sql =
        if SiteSetting.use_polymorphic_bookmarks
          "ON p.id = bookmarks.bookmarkable_id AND bookmarks.bookmarkable_type = 'Post'"
        else
          "ON p.id = bookmarks.post_id"
        end
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
        FROM bookmarks
        JOIN posts p
        #{post_bookmark_join_sql}
        JOIN topics t
        ON t.id = p.topic_id
        JOIN categories c
        ON c.id = t.category_id
        JOIN users u
        ON u.id = t.user_id
        WHERE bookmarks.created_at BETWEEN :start_date AND :end_date
        AND ((:exclude_staff = false) OR (u.admin = false AND u.moderator = false))
        AND c.id = :cat_id
        AND t.deleted_at IS NULL
        AND t.visible = true
        AND p.deleted_at IS NULL
        GROUP BY t.id, category_slug, category_name, c.id, username, uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT :limit
      SQL
    end

    def review_topic_exists?(review_year)
      TopicCustomField
        .find_by(name: ::YearlyReview::POST_CUSTOM_FIELD, value: review_year.to_s)
        &.topic
        .present?
    end
  end
end
