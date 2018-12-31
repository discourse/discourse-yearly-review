module YearlyReviewHelper
  def avatar_image(username, uploaded_avatar_id)
    template = User.avatar_template(username, uploaded_avatar_id).gsub(/{size}/, '25')
    "<img src='#{template}' class='avatar'/>"
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

  def emoji_for_action(action)
    return unless action

    unless SiteSetting.enable_emoji
      return action
    end

    case action
    when 'likes'
      emoji = 'heart'
    when 'replies'
      emoji = 'leftwards_arrow_with_hook'
    when 'bookmarks'
      emoji = 'bookmark'
    else
      return ''
    end

    url = Emoji.url_for(emoji)
    emoji_sym = ":#{emoji}:"
    "<img src='#{url}' title='#{emoji_sym}' class='emoji' alt='#{emoji_sym}'/>"
  end
end
