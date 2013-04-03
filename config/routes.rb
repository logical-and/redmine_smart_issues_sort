if Rails::VERSION::MAJOR >= 3
  RedmineApp::Application.routes.draw do
    match 'smart_issues_sort/autocomplete_for_category', :to => 'smart_issues_sort#autocomplete_for_category', :via => :post
  end
else
  ActionController::Routing::Routes.draw do |map|
    map.with_options :controller => 'smart_issues_sort' do |issues_routes|
      issues_routes.with_options :conditions => {:method => :post} do |issues_views|
        issues_views.connect 'smart_issues_sort/autocomplete_for_category', :action => 'autocomplete_for_category'
      end
    end
  end
end
