
class SmartIssuesSortController < ApplicationController
  def autocomplete_for_category
    @categories = IssueQuery.all(:conditions => ["LOWER(category) LIKE LOWER(?)", "#{params[:category]}%"],
                              :limit => 200,
                              :order => 'category ASC').collect{|q| q.category}.uniq
    render :layout => false
  end
end


