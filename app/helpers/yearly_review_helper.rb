module YearlyReviewHelper
  def avatar_image(username, uploaded_avatar_id)
    template = User.avatar_template(username, uploaded_avatar_id).gsub(/{size}/, '25')
    "<img src='#{template}'class='avatar'/>"
  end

  def user_link(username)
    "<a class='mention' href='/u/#{username}'>@#{username}</a>"
  end

  def class_from_key(key)
    key.gsub('_', '-')
  end
end
