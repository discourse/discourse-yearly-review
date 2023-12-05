import { withPluginApi } from "discourse/lib/plugin-api";
import YearlyReviewAdminNotice from "discourse/plugins/discourse-yearly-review/discourse/components/yearly-review-admin-notice";

export default {
  name: "yearly-review-admin-notice",
  initialize(container) {
    withPluginApi("1.18.0", (api) => {
      const siteSettings = container.lookup("service:site-settings");

      if (!siteSettings.yearly_review_enabled) {
        return;
      }

      // Only show this in December of the current year (getMonth is 0-based).
      const now = new Date();
      if (now.getMonth() === 11) {
        api.renderInOutlet("admin-dashboard-top", YearlyReviewAdminNotice);
      }
    });
  },
};
