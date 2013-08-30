require_dependency 'issue_query'
require 'smart_issues_sort'
require 'sis_asset_helpers'

module SmartIssuesSort
  module Patches
    module QuerySortCriteriaPatch
      def self.included(base) # :nodoc:
        base.send(:include, InstanceMethods)
        base.class_eval do
          unloadable
          alias_method_chain :issues, :parent_sort
          alias_method_chain :issue_ids, :parent_sort if IssueQuery.method_defined?(:issue_ids)
        end
      end
     
      module InstanceMethods
        def issues_with_parent_sort(options={})
          #def_logger=logger
          def_logger=nil
          def_logger.info("QG Info: Name: #{name}, new record: #{new_record? ? "1" : "0"}") if def_logger
          find_ids=options.delete(:find_ids)
          if (respond_to?(:sort_by_parent_first) && sort_by_parent_first == false && !new_record?) ||
          # default columns plugin compatibility
              (new_record? && name != '_QPP_' && SIS_AssetHelpers::settings['prepend_parent_sort'] != '1') ||
              (new_record? && name == '_QPP_' && respond_to?(:sort_by_parent_first) && sort_by_parent_first == false)
            parent_sort_options=[]
          else
            parent_sort_options=['issues.lft asc']
          end

          order_option = [group_by_sort_order, parent_sort_options ,options[:order]].reject {|s| s.blank?}.join(',')
          options_converted=SmartIssuesSortVVK::convert_sql_options_to_smart_options(order_option)

          if options_converted[:parent_involved] == false && SIS_AssetHelpers::settings['use_default_sort'] == '1'
            return issues_without_parent_sort(options) unless find_ids
            return issue_ids_without_parent_sort(options)
          end

          def_logger.info do
            s=''
            s << "#{order_option}\n"
            s << "QUERY order: \n"
            options_converted[:options].each do |o|
              s << "  #{o[0].to_s}#{o[1]==0 ? '' : " #{o[1].to_s}"} #{o[2].to_s}\n"
            end
            s
          end if def_logger

          joins = (order_option && order_option.include?('authors')) ? "LEFT OUTER JOIN users authors ON authors.id = #{Issue.table_name}.author_id" : nil
          options[:joins] = joins if joins
          options[:find_conditions] = statement
          sorted_issues=SmartIssuesSortVVK::get_issues_sorted_list_from_db(
              options_converted[:options],options,find_ids,
              SIS_AssetHelpers::settings['nil_values_first'] != '1' ? false : true,
              def_logger)

          unless find_ids
            if has_column?(:spent_hours)
              Issue.load_visible_spent_hours(sorted_issues)
            end
          end
          sorted_issues
        rescue ::ActiveRecord::StatementInvalid => e
          raise StatementInvalid.new(e.message)
        end

        def issue_ids_with_parent_sort(options={})
          issues_with_parent_sort(options.merge(:find_ids => true))
        end
      end
    end

    module GanttChartPatch
      def self.included(base) # :nodoc:
        base.send(:include, InstanceMethods)
        base.class_eval do
          unloadable
          #alias_method_chain :sort_issues!, :parent_sort
        end
      end

      module InstanceMethods
        def sort_issues_with_parent_sort!(issues)
          sort_options = [
            [:issue_parent,0,:asc],
            [:issue,:start_date,:asc],
            [:issue,:due_date,:asc]
          ]
          SmartIssuesSortVVK::get_issues_sorted_list(sort_options,issues,true)
        end
      end
    end
  end
end

if Redmine::VERSION::MAJOR > 2 || 
   (Redmine::VERSION::MAJOR == 2 && Redmine::VERSION::MINOR >= 3)
   unless IssueQuery.included_modules.include? SmartIssuesSort::Patches::QuerySortCriteriaPatch
    IssueQuery.send(:include, SmartIssuesSort::Patches::QuerySortCriteriaPatch) 
  end
else
   unless Query.included_modules.include? SmartIssuesSort::Patches::QuerySortCriteriaPatch
     Query.send(:include, SmartIssuesSort::Patches::QuerySortCriteriaPatch)
   end
end

unless Redmine::Helpers::Gantt.included_modules.include? SmartIssuesSort::Patches::GanttChartPatch
  Redmine::Helpers::Gantt.send(:include, SmartIssuesSort::Patches::GanttChartPatch)
end

if Redmine::Plugin.registered_plugins.keys.include? :redmine_better_gantt_chart
  unless Redmine::Helpers::BetterGantt.included_modules.include? SmartIssuesSort::Patches::GanttChartPatch
    Redmine::Helpers::BetterGantt.send(:include, SmartIssuesSort::Patches::GanttChartPatch)
  end
end
