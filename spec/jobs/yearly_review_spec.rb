require 'rails_helper'

# Todo: make sure tests won't fail in January.
describe Jobs::YearlyReview do
  let(:top_review_user) { Fabricate(:user, username: 'top_review_user') }
  let(:reviewed_user) { Fabricate(:user, username: 'review_user') }

  describe 'publishing the topic' do
    context 'January 1, 2019' do
      before do
        freeze_time DateTime.parse('2019-01-01')
        Fabricate(:topic, created_at: 1.month.ago)
      end
      it 'publishes a review topic' do
        Jobs::YearlyReview.new.execute({})
        topic = Topic.last

        expect(topic.title).to eq(I18n.t('yearly_review.topic_title', year: 2018))
      end
    end

    context 'February 1, 2019' do
      before do
        freeze_time DateTime.parse('2019-02-01')
        Fabricate(:topic, created_at: 2.months.ago, title: 'A topic from 2018')
      end
      it "doesn't publish a review topic" do
        Jobs::YearlyReview.new.execute({})
        topic = Topic.last

        expect(topic.title).to eq('A topic from 2018')
      end
    end
  end

  describe 'review categories' do
    before do
      freeze_time DateTime.parse('2019-01-01')
    end
    it 'only displays data from public categories' do
      review_category = Fabricate(:category)
      non_review_category = Fabricate(:category)
      group = Fabricate(:group)
      non_review_category.set_permissions(group => :full)
      non_review_category.save
      Fabricate(:topic, category_id: non_review_category.id, user: reviewed_user, created_at: 1.month.ago)
      Fabricate(:topic, category_id: review_category.id, user: top_review_user, created_at: 1.month.ago)

      Jobs::YearlyReview.new.execute({})
      topic = Topic.last
      raw = Post.where(topic_id: topic.id).first.raw

      expect(raw).not_to have_tag('td', text: /@review_user/)
      expect(raw).to have_tag('td', text: /@top_review_user/)
    end
  end

end
