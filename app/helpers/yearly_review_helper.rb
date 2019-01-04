module YearlyReviewHelper
  def avatar_image(username, uploaded_avatar_id)
    template = User.avatar_template(username, uploaded_avatar_id).gsub(/{size}/, '50')
    "<img src='#{template}' class='avatar' height='25' width='25'/>"
  end

  def user_link(username)
    "<a class='mention' href='/u/#{username}'>@#{username}</a>"
  end

  def topic_link(title, slug, topic_id)
    link = "#{Discourse.base_url}/t/#{slug}/#{topic_id}"
    "<a href='#{link}'>#{title}</a>"
  end

  def class_from_key(key)
    key.gsub('_', '-')
  end

  def slug_from_name(name)
    name.downcase.gsub(' ', '-')
  end

  def badge_link(name, id, more)
    url = "#{Discourse.base_url}/badges/#{id}/#{slug_from_name(name)}"
    "<a class='more-badge-users' href='#{url}'>#{t('yearly_review.more_badge_users', more: more)}</a>"
  end
end
