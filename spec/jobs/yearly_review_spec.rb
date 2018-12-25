require 'rails_helper'

# Todo: make sure tests won't fail in January.
describe Jobs::YearlyReview do
  describe 'query results' do
    let (:review_creator) { Fabricate(:user, admin: true) }
    let (:top_review_user) { Fabricate(:user, username: 'top_review_user') }
    let(:review_user) { Fabricate(:user, username: 'review_user') }

    context 'most topics' do
      before do
        freeze_time DateTime.parse('2018-02-01')
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
        freeze_time DateTime.parse('2018-02-01')
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

    context 'likes given and received' do
      let(:reviewed_topic) { Fabricate(:topic) }
      before do
        freeze_time DateTime.parse('2018-02-01')
        5.times do
          post = Fabricate(:post, topic: reviewed_topic, user: review_user)
          UserAction.create!(action_type: PostActionType.types[:like],
                             user_id: review_user.id,
                             acting_user_id: top_review_user.id,
                             target_post_id: post.id,
                             target_topic_id: reviewed_topic.id)
        end
        post = Fabricate(:post, topic: reviewed_topic, user: top_review_user)
        UserAction.create!(action_type: PostActionType.types[:like],
                           user_id: top_review_user.id,
                           acting_user_id: review_user.id,
                           target_post_id: post.id,
                           target_topic_id: reviewed_topic.id)
      end
      it 'should rank the users correctly' do
        Jobs::YearlyReview.new.execute(review_user: review_creator)
        topic = Topic.where(archetype: 'regular').last
        raw = Post.where(topic_id: topic.id).first.raw

        expect(raw).to have_tag('table.likes-given tr.user-row-0') { with_tag('td', text: /5/) }
        expect(raw).to have_tag('table.likes-given tr.user-row-0') { with_tag('td', text: /top_review_user/) }
        expect(raw).to have_tag('table.likes-given tr.user-row-1') { with_tag('td', text: /1/) }
        expect(raw).to have_tag('table.likes-given tr.user-row-1') { with_tag('td', text: /review_user/) }

        expect(raw).to have_tag('table.likes-received tr.user-row-0') { with_tag('td', text: /5/) }
        expect(raw).to have_tag('table.likes-received tr.user-row-0') { with_tag('td', text: /review_user/) }
        expect(raw).to have_tag('table.likes-received tr.user-row-1') { with_tag('td', text: /1/) }
        expect(raw).to have_tag('table.likes-received tr.user-row-1') { with_tag('td', text: /top_review_user/) }
      end
    end

    context 'featured badge users' do
      SiteSetting.yearly_review_featured_badge = 'Editor'
      before do
        freeze_time DateTime.parse('2018-02-01')
        badge = Badge.find_by(name: SiteSetting.yearly_review_featured_badge)
        5.times do
          user = Fabricate(:user)
          BadgeGranter.grant(badge, user)
        end
      end
      it 'features the correct number of users' do
        Jobs::YearlyReview.new.execute(review_user: review_creator)
        topic = Topic.where(archetype: 'regular').last
        raw = Post.where(topic_id: topic.id).first.raw

        expect(raw).to have_tag('a.mention', count: 5)
      end
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
end
