import Ember from 'ember';
import { ajax } from 'discourse/lib/ajax';
import { popupAjaxError } from 'discourse/lib/ajax-error';

export default Ember.Component.extend({
  classNames: ['create-review'],

  actions: {
    submit: function() {
      ajax("/admin/plugins/yearly-review/create.json", {
        type: "POST",
      }).then(() => {
        // Todo: the message will indicate that the report is being created, will be notified by message when done.
        bootbox.alert(I18n.t('yearly_review.report_being_created'));
      }).catch(popupAjaxError);
    },
  }
});
