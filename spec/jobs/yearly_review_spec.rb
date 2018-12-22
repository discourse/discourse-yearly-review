require 'rails_helper'

# Todo: improve this.
describe Jobs::YearlyReview do
  describe 'creating a topic' do
    let(:review_user) { Fabricate( :user, admin: true ) }
    let(:regular_user) { Fabricate( :user, username: 'regular_user' ) }
    let(:review_category) { Fabricate( :category, name: 'scratch')}
    let(:non_review_category) { Fabricate( :category, name: 'sniff') }
    let(:review_topic) { Fabricate( :topic, title: 'A well liked topic', category: review_category) }
    let(:non_review_topic) { Fabricate( :topic, title: 'This topic will not be reviewed', category: non_review_category)}

    it 'should create a topic with the correct title' do
      Jobs::YearlyReview.new.execute(review_user: review_user)
      topic = Topic.where(archetype: 'regular').last
      expect(topic.title).to eq(SiteSetting.yearly_review_title)
    end

    it 'should not display headings for sections without data' do
      Jobs::YearlyReview.new.execute(review_user: review_user)
      topic = Topic.where(archetype: 'regular').last
      post = Post.where(topic_id: topic.id).first

      expect(post.raw).not_to have_tag('h3')
    end

    it 'should display headings for sections with data' do
      review_topic
      Jobs::YearlyReview.new.execute(review_user: review_user)
      topic = Topic.where(archetype: 'regular').last
      post = Post.where(topic_id: topic.id).first

      expect(post.raw).to have_tag('h3', :text => 'Topics Created')
    end
  end

  describe 'review topic settings' do
      let(:review_user) { Fabricate( :user, admin: true ) }
      let(:regular_user) { Fabricate( :user, username: 'regular_user' ) }
      let(:unreviewed_user) { Fabricate( :user, username: 'unreviewed_user') }
      let(:review_category) { Fabricate( :category, name: 'scratch') }
      let(:non_review_category) { Fabricate( :category, name: 'sniff') }
      let(:review_topic) { Fabricate( :topic, title: 'A well liked topic', user: regular_user, category_id: review_category.id) }
      let(:non_review_topic) { Fabricate( :topic, title: 'This topic will not be reviewed', user: unreviewed_user, category_id: non_review_category.id)}

      it 'should respect the review_categories setting' do
        SiteSetting.yearly_review_categories = "#{review_category.id}"
        review_category
        non_review_category
        review_topic
        non_review_topic

        Jobs::YearlyReview.new.execute(review_user: review_user)
        topic = Topic.where(archetype: 'regular').last
        post = Post.where(topic_id: topic.id).first

        expect(post.raw).to have_tag('a', :text => '@regular_user')
        expect(post.raw).not_to have_tag('a', :text => '@unreviewed_user')
      end
  end
end
