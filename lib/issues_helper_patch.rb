
module SmartIssuesSort
  module Patches
    module RenderQueriesPatch
      def self.included(base) # :nodoc:
        base.send(:include, InstanceMethods)
        base.class_eval do
          unloadable
          alias_method_chain :render_sidebar_queries, :category
          alias_method_chain :sidebar_queries, :category
        end
      end

      module InstanceMethods
        def sidebar_queries_with_category
          unless @sidebar_queries
            @sidebar_queries = Query.visible.all(
              :order => "#{Query.table_name}.name ASC",
              # Project specific queries and global queries
              :conditions => (@project.nil? ? ["project_id IS NULL"] : ["project_id IS NULL OR project_id = ?", @project.id]),
              # Make sure we load category as well
              :select => [:name, :category, :is_public]
            )
          end
          @sidebar_queries
        end

        def render_sidebar_queries_with_category
          out = ''.html_safe
          unless sidebar_queries.empty?
            return render_sidebar_queries_without_category unless sidebar_queries[0].respond_to?(:category)
            out << "<h3>#{l(:label_query_plural)}</h3>".html_safe
            sidebar_queries.group_by {|q| q.category || "" }.sort.each do |query_group_name, queries|
              unless query_group_name.empty?
                out << "<h4>#{query_group_name}</h4>".html_safe
              end
              queries.each do |query|
                for_all_projects = query.project.nil? ? true : false
                link_to_hash={:controller => 'issues', :action => 'index', :query_id => query, :project_id => @project }
                link_to_hash[:project_id]=@project
                query.project = @project unless @project.nil?
                out << link_to(h(query.name), link_to_hash, :class => (query.is_public? ? 'icon icon-fav-off' : 'icon icon-fav'))
                if for_all_projects && @project != nil
                  link_to_hash[:project_id]=nil
                  query.project = nil
                  out << " [#{link_to('A', link_to_hash)}]".html_safe
                  issue_count = ''
                else
                  issue_count = " (#{query.issue_count.to_s rescue '???'})"
                end
                out << "#{issue_count}<br />".html_safe
              end
            end
          end
          out
        end
      end
    end
  end
end

unless IssuesHelper.included_modules.include? SmartIssuesSort::Patches::RenderQueriesPatch
  IssuesHelper.send(:include, SmartIssuesSort::Patches::RenderQueriesPatch)
end
