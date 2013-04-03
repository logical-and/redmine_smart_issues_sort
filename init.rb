require 'redmine'
require 'dispatcher' unless Rails::VERSION::MAJOR >= 3
require 'sis_asset_helpers'

Redmine::Plugin.register SIS_AssetHelpers::PLUGIN_NAME do
  name 'Smart issues sort plugin'
  author 'Vitaly Klimov'
  author_url 'mailto:vitaly.klimov@snowbirdgames.com'
  description "Plugin correctly sorts issues, adds options to sort by parent always and adds categories support for queries. Queries category mechanism is taken from Andrew Chaika's 'Issues Group' plugin"
  version '0.3.1'
  requires_redmine :version_or_higher => '1.3.0'

    settings(:partial => 'settings/smart_issues_sort_settings',
             :default => {
               'prepend_parent_sort' => '0',
               'use_default_sort' => '1',
               'nil_values_first' => '1'
             })

end

if Rails::VERSION::MAJOR >= 3
  ActionDispatch::Callbacks.to_prepare do
    require 'issues_helper_patch'
    require 'query_patch'
  end
else
  Dispatcher.to_prepare SIS_AssetHelpers::PLUGIN_NAME do
    require_dependency 'issues_helper_patch'
    require_dependency 'query_patch'
  end
end
