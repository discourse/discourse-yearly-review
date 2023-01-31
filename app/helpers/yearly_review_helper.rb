# frozen_string_literal: true

module YearlyReviewHelper
  include ActionView::Helpers::NumberHelper

  def avatar_image(username, uploaded_avatar_id)
    template = User.avatar_template(username, uploaded_avatar_id).gsub(/{size}/, "50")
    "![avatar\\|25x25](#{template})"
  end

  def user_link(username)
    "@#{username}"
  end

  def topic_link(title, slug, topic_id)
    link = "#{Discourse.base_url}/t/#{slug}/#{topic_id}"
    "[#{title}](#{link})"
  end

  def class_from_key(key)
    key.gsub("_", "-")
  end

  def slug_from_name(name)
    name.downcase.gsub(" ", "-")
  end

  def badge_link(name, id, more)
    url = "#{Discourse.base_url}/badges/#{id}/#{slug_from_name(name)}"
    "<a class='more-badge-users' href='#{url}'>#{t("yearly_review.more_badge_users", more: more)}</a>"
  end

  def category_link(name)
    category = Category.find_by(name: name)
    if category.parent_category_id
      parent_category = Category.find(category.parent_category_id)
      url = "#{Discourse.base_url}/c/#{parent_category.slug}/#{category.slug}/l/top"
    else
      url = "#{Discourse.base_url}/c/#{category.slug}/l/top"
    end
    link_text = t("yearly_review.category_topics_title", category: name)
    "<a href='#{url}'>#{link_text}</a>"
  end

  def user_visits_link
    if SiteSetting.enable_user_directory && !SiteSetting.hide_user_profiles_from_public
      url = "#{Discourse.base_url}/u?order=days_visited&period=yearly"
      "<br><a href='#{url}'>#{t("yearly_review.all_yearly_visits")}</a>"
    end
  end

  def format_number(number)
    number_to_human(number, units: { thousand: "k" }, format: "%n%u")
  end

  def table_row(*values)
    "|#{values.join("|")}|"
  end

  def table_header(*labels)
    headings = labels.map { |label| I18n.t(label) }
    "|#{headings.join("|")}|"
  end
end
