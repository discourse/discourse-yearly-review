require 'rails_helper'

# Todo: this still needs work.
describe Jobs::YearlyReview do
  describe 'creating a topic' do
    let(:review_creator) { Fabricate(:user, admin: true) }
    let(:regular_user) { Fabricate(:user, username: 'regular_user') }
    let(:review_category) { Fabricate(:category, name: 'scratch') }
    let(:non_review_category) { Fabricate(:category, name: 'sniff') }
    let(:review_topic) { Fabricate(:topic, title: 'A well liked topic', category: review_category) }
    let(:non_review_topic) { Fabricate(:topic, title: 'This topic will not be reviewed', category: non_review_category) }

    it 'should create a topic with the correct title' do
      Jobs::YearlyReview.new.execute(review_user: review_creator)
      topic = Topic.where(archetype: 'regular').last
      expect(topic.title).to eq(SiteSetting.yearly_review_title)
    end
  end

  describe 'review topic settings' do
    let(:review_creator) { Fabricate(:user, admin: true) }
    let(:regular_user) { Fabricate(:user, username: 'regular_user') }
    let(:unreviewed_user) { Fabricate(:user, username: 'unreviewed_user') }
    let(:review_category) { Fabricate(:category, name: 'scratch') }
    let(:non_review_category) { Fabricate(:category, name: 'sniff') }
    let(:review_topic) { Fabricate(:topic, title: 'A well liked topic', user: regular_user, category_id: review_category.id) }
    let(:non_review_topic) { Fabricate(:topic, title: 'This topic will not be reviewed', user: unreviewed_user, category_id: non_review_category.id) }

      it 'should respect the review_categories setting' do
        SiteSetting.yearly_review_categories = "#{review_category.id}"
        review_category
        non_review_category
        review_topic
        non_review_topic

        Jobs::YearlyReview.new.execute(review_user: review_creator)
        topic = Topic.where(archetype: 'regular').last
        post = Post.where(topic_id: topic.id).first

        expect(post.raw).to have_tag('a', text: '@regular_user')
        expect(post.raw).not_to have_tag('a', text: '@unreviewed_user')
      end
  end

  describe 'query results' do
    let (:review_creator) { Fabricate(:user, admin: true) }
    let (:top_review_user) { Fabricate(:user, username: 'top_review_user') }
    let(:review_user) { Fabricate(:user, username: 'review_user') }
    context 'most topics' do

      before do
        5.times { Fabricate(:topic, user: top_review_user) }
        Fabricate(:topic, user: review_user)
      end

      it 'should rank the users correctly' do
        Jobs::YearlyReview.new.execute(review_user: review_creator)
        topic = Topic.where(archetype: 'regular').last
        raw = Post.where(topic_id: topic.id).first.raw

        expect(raw).to have_tag('table.topics-created tr.user-row-0') { with_tag('td', text: /5/) }
        expect(raw).to have_tag('table.topics-created tr.user-row-1') { with_tag('td', text: /1/) }
      end
    end

    context 'most replies' do
      let(:reviewed_topic) { Fabricate(:topic) }
      it 'should rank the users correctly' do
        5.times do
          Fabricate(:post, topic: reviewed_topic, user: top_review_user)
        end
        Fabricate(:post, topic: reviewed_topic, user: review_user)

        Jobs::YearlyReview.new.execute(review_user: review_creator)
        topic = Topic.where(archetype: 'regular').last
        raw = Post.where(topic_id: topic.id).first.raw

        expect(raw).to have_tag('table.replies-created tr.user-row-0') { with_tag('td', text: /4/) }
        expect(raw).to have_tag('table.replies-created tr.user-row-1') { with_tag('td', text: /1/) }
      end
    end

    context 'most likes given' do

    end
  end
end
