require 'rails_helper'

describe Jobs::YearlyReview do
  describe 'creating a topic' do
    let(:review_user) { Fabricate( :user, admin: true ) }

    it 'should create a topic with the correct title' do
      Jobs::YearlyReview.new.execute(review_user: review_user)
      topic = Topic.where(archetype: 'regular').last
      expect(topic.title).to eq(SiteSetting.yearly_review_title)
    end

    it 'should only display headings for sections with data' do
      Jobs::YearlyReview.new.execute(review_user: review_user)
      topic = Topic.where(archetype: 'regular').last
      post = Post.where(topic_id: topic.id).first
      puts "RAW #{post.raw}"
      expect(post.raw).not_to have_tag('h3')
    end
  end

end
