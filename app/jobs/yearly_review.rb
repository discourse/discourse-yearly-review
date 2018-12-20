require_relative '../../app/helpers/yearly_review_helper'
module ::Jobs
  class YearlyReview < ::Jobs::Base
    def execute(args)
      render_review(args[:review_user])
    end

    def render_review(review_user)
      review_title = SiteSetting.yearly_review_title.blank? ? '2018 in Review' : SiteSetting.yearly_review_title
      review_categories = review_categories_from_settings
      review_featured_badge = SiteSetting.yearly_review_featured_badge
      review_publish_category = SiteSetting.yearly_review_publish_category
      review_start = Time.parse("2018-01-01").beginning_of_day
      review_end = review_start.end_of_year
      review_bot = User.find(-3)

      most_topics = most_topics review_categories, review_start, review_end
      most_replies = most_replies review_categories, review_start, review_end
      most_likes = most_likes_given review_start, review_end
      # todo: use this!
      most_visits = most_visits review_start, review_end
      most_liked_topics = most_liked_topics review_categories, review_start, review_end
      most_liked_posts = most_liked_posts review_categories, review_start, review_end
      most_replied_to_topics = most_replied_to_topics review_categories, review_start, review_end
      featured_badge_users = review_featured_badge.blank? ? nil : featured_badge_users(review_featured_badge, review_start, review_end)

      user_stats = [
        {key: 'topics_created', users: most_topics},
        {key: 'replies_created', users: most_replies},
        {key: 'likes_given', users: most_likes},
      ]

      view = ActionView::Base.new(ActionController::Base.view_paths,
                                  user_stats: user_stats,
                                  most_liked_topics: most_liked_topics,
                                  most_liked_posts: most_liked_posts,
                                  most_replied_to_topics: most_replied_to_topics,
                                  featured_badge_users: featured_badge_users)
      view.class_eval do
        include YearlyReviewHelper
      end

      output = view.render :template => "yearly_review", formats: :html, layout: false

      opts = {
        # todo: remove the random string
        title: "#{review_title} - #{rand(100000)}",
        raw: output,
        category: review_publish_category,
        skip_validations: true
      }

      post = PostCreator.create!(review_bot, opts)
      topic_url = "#{Discourse.base_url}/t/#{post.topic.slug}/#{post.topic.id}"
      notify_user(review_user, topic_url)
    end

    def notify_user(review_user, topic_url)
      SystemMessage.create(review_user, 'review_topic_created', topic_url: topic_url)
    end

    def review_categories_from_settings
      if SiteSetting.yearly_review_categories.blank?
        Category.where(read_restricted: false).pluck(:id)
      else
        SiteSetting.yearly_review_categories.split('|').map {|x| x.to_i}
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
        GROUP BY t.user_id, u.username, u.uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT 15
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
        AND p.created_at >= '#{start_date}'
        AND p.created_at <= '#{end_date}'
        AND t.category_id IN (#{categories.join(',')})
        GROUP BY p.user_id, u.username, u.uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT 15
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
      SQL

      DB.query(sql)
    end

    def most_visits(start_date, end_date)
      # todo: add category filter
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
        LIMIT 15
      SQL

      DB.query(sql)
    end

    def most_likes_given(start_date, end_date)
      # todo: filter by category
      sql = <<~SQL
        SELECT
        ua.acting_user_id,
        u.username,
        u.uploaded_avatar_id,
        COUNT(ua.user_id) AS action_count
        FROM user_actions ua
        JOIN users u
        ON u.id = ua.acting_user_id
        WHERE u.id > 0
        AND ua.created_at >= '#{start_date}'
        AND ua.created_at <= '#{end_date}'
        AND ua.action_type = 2
        GROUP BY ua.acting_user_id, u.username, u.uploaded_avatar_id
        ORDER BY action_count DESC
        LIMIT 15
      SQL

      DB.query(sql)
    end

    def likes_in_topic_sql
      <<~SQL
        SELECT
        t.id,
        t.slug AS topic_slug,
        t.title,
        c.slug AS category_slug,
        c.name AS category_name,
        c.id AS category_id,
        NULL AS post_number,
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
        AND c.read_restricted = 'false'
        AND t.deleted_at IS NULL
        GROUP BY t.id, category_slug, category_name, c.id
        ORDER BY action_count DESC
        LIMIT 5
      SQL
    end

    def most_liked_posts_sql
      <<~SQL
        SELECT
        t.id,
        p.post_number,
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
        AND c.read_restricted = 'false'
        AND p.deleted_at IS NULL
        AND t.deleted_at IS NULL
        GROUP BY p.id, t.id, topic_slug, category_slug, category_name, c.id
        ORDER BY action_count DESC
        LIMIT 5
      SQL
    end


    def most_replied_to_topics_sql
      <<~SQL
        SELECT
        t.id,
        NULL AS post_number,
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
        AND c.read_restricted = 'false'
        AND t.deleted_at IS NULL
        GROUP BY t.id, topic_slug, category_slug, category_name, c.id
        ORDER BY action_count DESC
        LIMIT 5
      SQL
    end

    def most_liked_topics cat_ids, start_date, end_date
      category_topics(start_date, end_date, cat_ids, likes_in_topic_sql)
    end

    def most_liked_posts cat_ids, start_date, end_date
      category_topics(start_date, end_date, cat_ids, most_liked_posts_sql)
    end

    def most_replied_to_topics cat_ids, start_date, end_date
      category_topics(start_date, end_date, cat_ids, most_replied_to_topics_sql)
    end

    def category_topics(start_date, end_date, category_ids, sql)
      data = []
      category_ids.each do |cat_id|
        DB.query(sql, start_date: start_date, end_date: end_date, cat_id: cat_id).each_with_index do |row, i|
          if row
            title = category_link_title(row.category_slug, row.category_id, row.category_name)
            data << "<h4>#{title}</h4>" if i == 0
            data << topic_link(row.topic_slug, row.id, row.post_number)
          end
        end
      end
      data
    end

    def topic_link(slug, topic_id, post_number = nil)
      url = " #{Discourse.base_url}/t/#{slug}/#{topic_id}"
      url += "/#{post_number}" if post_number
      url.strip
    end

    def category_link_title(slug, id, name)
      "<a class='hashtag' href='/c/#{slug}/#{id}'><h4>##{name}</h4></a> \r\r"
    end
  end
end
