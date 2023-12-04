import Component from "@glimmer/component";
import I18n from "discourse-i18n";
import replaceEmoji from "discourse/helpers/replace-emoji";
import htmlSafe from "discourse-common/helpers/html-safe";
import { inject as service } from "@ember/service";
import i18n from "discourse-common/helpers/i18n";
import getURL from "discourse-common/lib/get-url";

export function janNextYear() {
  return new Date(new Date().getFullYear() + 1, 0, 1);
}

export default class extends Component {
  @service siteSettings;

  get toBeCreatedDate() {
    return moment(janNextYear()).format(I18n.t("dates.full_with_year_no_time"));
  }

  get settingsUrl() {
    return getURL("/admin/site_settings/category/plugins?filter=plugin%3Adiscourse-yearly-review");
  }

  <template>
    <div class="yearly-review-admin-notice alert alert-info">
      {{replaceEmoji (htmlSafe (i18n "yearly_review.admin_notice" to_be_created_date=this.toBeCreatedDate settings_url=this.settingsUrl))}}
    </div>
  </template>
 }
