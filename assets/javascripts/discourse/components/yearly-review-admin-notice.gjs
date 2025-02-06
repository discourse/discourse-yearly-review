import Component from "@glimmer/component";
import { htmlSafe } from "@ember/template";
import replaceEmoji from "discourse/helpers/replace-emoji";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

export function janNextYear() {
  return new Date(new Date().getFullYear() + 1, 0, 1);
}

export default class YearlyReviewAdminNotice extends Component {
  get toBeCreatedDate() {
    return moment(janNextYear()).format(i18n("dates.full_with_year_no_time"));
  }

  get settingsUrl() {
    return getURL(
      "/admin/site_settings/category/plugins?filter=plugin%3Adiscourse-yearly-review"
    );
  }

  <template>
    <div class="yearly-review-admin-notice alert alert-info">
      {{replaceEmoji
        (htmlSafe
          (i18n
            "yearly_review.admin_notice"
            to_be_created_date=this.toBeCreatedDate
            settings_url=this.settingsUrl
          )
        )
      }}
    </div>
  </template>
}
