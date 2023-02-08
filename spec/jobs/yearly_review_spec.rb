# frozen_string_literal: true

require "rails_helper"

describe Jobs::YearlyReview do
  class Helper
    extend YearlyReviewHelper
  end

  SiteSetting.yearly_review_enabled = true
  let(:category) { Fabricate(:category) }
  let(:top_review_user) { Fabricate(:user, username: "top_review_user") }
  let(:reviewed_user) { Fabricate(:user, username: "reviewed_user") }
  describe "publishing the topic" do
    describe "on January 1st" do
      before do
        SiteSetting.yearly_review_publish_category = category.id
        freeze_time DateTime.parse("#{::YearlyReview.current_year}-01-01")
        Fabricate(:topic, created_at: 1.month.ago)
      end

      it "publishes a review topic" do
        Jobs::YearlyReview.new.execute({})
        topic = Topic.last
        expect(topic.title).to eq(
          I18n.t("yearly_review.topic_title", year: ::YearlyReview.last_year),
        )
        expect(topic.first_post.custom_fields).to eq(
          YearlyReview::POST_CUSTOM_FIELD => ::YearlyReview.last_year.to_s,
        )
      end
    end

    describe "on February 1st" do
      before do
        freeze_time DateTime.parse("#{::YearlyReview.current_year}-02-01")
        Fabricate(
          :topic,
          created_at: 2.months.ago,
          title: "A topic from #{::YearlyReview.last_year}",
        )
      end

      it "doesn't publish a review topic" do
        Jobs::YearlyReview.new.execute({})
        topic = Topic.last
        expect(topic.title).to eq("A topic from #{::YearlyReview.last_year}")
      end
    end

    describe "after the review has been published" do
      before do
        SiteSetting.yearly_review_publish_category = category.id
        freeze_time DateTime.parse("#{::YearlyReview.current_year}-01-05")
        Fabricate(:topic, created_at: 1.month.ago)
        Jobs::YearlyReview.new.execute({})
        Fabricate(:topic, title: "The last topic published")
        Jobs::YearlyReview.new.execute({})
      end

      it "doesn't publish the review topic twice" do
        topic = Topic.last
        expect(topic.title).to eq("The last topic published")
      end
    end
  end

  describe "user stats" do
    before do
      freeze_time DateTime.parse("#{::YearlyReview.current_year}-01-01")
      SiteSetting.yearly_review_publish_category = category.id
    end

    describe "most topics" do
      before do
        5.times { Fabricate(:topic, user: top_review_user, created_at: 1.month.ago) }
        Fabricate(:topic, user: reviewed_user, created_at: 1.month.ago)
      end

      it "ranks topics created by users correctly" do
        Jobs::YearlyReview.new.execute({})
        raw = Topic.last.first_post.raw
        expect(raw).to have_tag("div.topics-created") { with_text(/\@top_review_user\|5/) }
        expect(raw).to have_tag("div.topics-created") { with_text(/\@reviewed_user\|1/) }
      end

      it "updates username correctly after anonymize the user" do
        Jobs.run_immediately!
        UserActionManager.enable
        stub_image_size

        upload = Fabricate(:upload, user: top_review_user)
        top_review_user.user_avatar =
          UserAvatar.new(user_id: top_review_user.id, custom_upload_id: upload.id)
        top_review_user.uploaded_avatar_id = upload.id
        top_review_user.save!

        Jobs::YearlyReview.new.execute({})
        post = Topic.last.first_post
        raw = post.raw
        expect(raw).to have_tag("div.topics-created") { with_text(/\@top_review_user\|5/) }
        expect(raw).to have_tag("div.topics-created") { with_text(%r{/top_review_user/50/}) }

        user = UserAnonymizer.new(top_review_user, Discourse.system_user, {}).make_anonymous
        raw = post.reload.raw
        expect(raw).to have_tag("div.topics-created") { with_text(/\@#{user.username}\|5/) }
        expect(raw).to have_tag("div.topics-created") { with_text(%r{/#{user.username}/50/}) }
      end
    end

    describe "most replies" do
      before do
        SiteSetting.max_consecutive_replies = 5
        SiteSetting.yearly_review_publish_category = category.id
        topic_user = Fabricate(:user)
        reviewed_topic = Fabricate(:topic, user: topic_user, created_at: 1.year.ago)
        Fabricate(:post, topic: reviewed_topic, user: topic_user)
        5.times do
          Fabricate(:post, topic: reviewed_topic, user: top_review_user, created_at: 1.month.ago)
        end
        Fabricate(:post, topic: reviewed_topic, user: reviewed_user, created_at: 1.month.ago)
      end

      it "ranks replies created by users correctly" do
        Jobs::YearlyReview.new.execute({})
        raw = Topic.last.first_post.raw
        expect(raw).to have_tag("div.replies-created") { with_text(/\@top_review_user\|5/) }
        expect(raw).to have_tag("div.replies-created") { with_text(/\@reviewed_user\|1/) }
      end
    end

    describe "most bookmarks" do
      let(:topic_user) { Fabricate(:user) }
      let(:reviewed_topic) { Fabricate(:topic, user: topic_user, created_at: 1.year.ago) }

      before do
        SiteSetting.yearly_review_publish_category = category.id
        SiteSetting.use_polymorphic_bookmarks = true
        10.times do
          Fabricate(:post, topic: reviewed_topic, created_at: 1.month.ago, user: top_review_user)
        end
        reviewed_topic.reload
        Fabricate(
          :bookmark,
          bookmarkable: reviewed_topic.posts[1],
          user: topic_user,
          created_at: 1.month.ago,
        )
        Fabricate(
          :bookmark,
          bookmarkable: reviewed_topic.posts[2],
          user: topic_user,
          created_at: 1.month.ago,
        )
        Fabricate(
          :bookmark,
          bookmarkable: reviewed_topic.posts[3],
          user: topic_user,
          created_at: 1.month.ago,
        )
        Fabricate(
          :bookmark,
          bookmarkable: reviewed_topic.posts[4],
          user: topic_user,
          created_at: 1.month.ago,
        )
        Fabricate(
          :bookmark,
          bookmarkable: reviewed_topic.posts[5],
          user: topic_user,
          created_at: 1.month.ago,
        )
      end

      it "ranks bookmarks created by users correctly" do
        Jobs::YearlyReview.new.execute({})
        topic = Topic.last
        raw = Post.where(topic_id: topic.id).second.raw
        expect(raw).to include(
          Helper.table_header("user", "topic", "rank_type.action_types.most_bookmarked"),
        )
        expect(raw).to include(
          Helper.table_row(
            Helper.avatar_image(
              reviewed_topic.user.username,
              reviewed_topic.user.uploaded_avatar_id,
            ),
            Helper.topic_link(reviewed_topic.title, reviewed_topic.slug, reviewed_topic.id),
            5,
          ),
        )
      end
    end

    describe "likes given and received" do
      SiteSetting.max_consecutive_replies = 20
      let(:reviewed_topic) { Fabricate(:topic, created_at: 1.year.ago) }
      before do
        11.times do
          post =
            Fabricate(:post, topic: reviewed_topic, user: reviewed_user, created_at: 1.month.ago)
          UserAction.create!(
            action_type: PostActionType.types[:like],
            user_id: reviewed_user.id,
            acting_user_id: top_review_user.id,
            target_post_id: post.id,
            target_topic_id: reviewed_topic.id,
            created_at: 1.month.ago,
          )
        end
        10.times do
          post =
            Fabricate(:post, topic: reviewed_topic, user: top_review_user, created_at: 1.month.ago)
          UserAction.create!(
            action_type: PostActionType.types[:like],
            user_id: top_review_user.id,
            acting_user_id: reviewed_user.id,
            target_post_id: post.id,
            target_topic_id: reviewed_topic.id,
            created_at: 1.month.ago,
          )
        end
      end

      it "should rank likes given and received correctly" do
        Jobs::YearlyReview.new.execute({})
        raw = Topic.last.first_post.raw
        expect(raw).to have_tag("div.likes-given") { with_text(/\@top_review_user\|11/) }
        expect(raw).to have_tag("div.likes-given") { with_text(/\@reviewed_user\|10/) }

        expect(raw).to have_tag("div.likes-received") { with_text(/\@reviewed_user\|11/) }
        expect(raw).to have_tag("div.likes-received") { with_text(/\@top_review_user\|10/) }
      end
    end
  end

  describe "featured badge" do
    let(:admin) { Fabricate(:user, admin: true) }
    let(:badge) { Fabricate(:badge) }
    before do
      SiteSetting.yearly_review_featured_badge = badge.name
      SiteSetting.yearly_review_publish_category = category.id
      freeze_time DateTime.parse("#{::YearlyReview.current_year}-01-01")
      16.times do
        user = Fabricate(:user)
        UserBadge.create!(
          badge_id: badge.id,
          user_id: user.id,
          granted_at: 1.month.ago,
          granted_by_id: admin.id,
        )
      end
    end

    it "it should only display the first 100 users" do
      Jobs::YearlyReview.new.execute({})
      raw = Topic.last.first_post.raw
      expect(raw).to include("[And 1 more...](")
    end
  end
end
