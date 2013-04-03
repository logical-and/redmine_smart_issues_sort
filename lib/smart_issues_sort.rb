
module SmartIssuesSortVVK
  # returns hash:
  # array of sort options converted to smart issues sort format (:options)
  # and boolean if parent sorting involved (:parent_involved)
  def self.convert_sql_options_to_smart_options(order_option)
    options_to_discard=%w(issues.root_id authors.firstname authors.id users.firstname users.id versions.name)
    parent_involved=false
    options_array=[]
    if order_option.include?('LIMIT')
      normalized_options=[]
      bracket_no=0
      c_str=''
      order_option.each_byte do |b|
        case b
          when ?(
            bracket_no+=1
          when ?)
            bracket_no-=1
          when ?,
            if bracket_no == 0
              normalized_options << c_str.strip
              c_str = ''
            else
              c_str << b
            end
          else
            c_str << b
        end
      end
      normalized_options << c_str.strip if c_str != ''

      order_option=[]
      normalized_options.each do |opt|
        unless opt.include?('LIMIT')
          order_option << opt
        else
          md=opt.match(/(.*)custom_field_id=([0-9]+)(.+)/)
          order_option << "cfield.#{md[2]}#{md[3][-4..-1]=='DESC' ? " DESC" : ''}" if md
        end
      end
    else
      order_option=order_option.split(',')
    end

    order_option.each do |o|
      tmp_a=o.strip.split(' ')
      unless options_to_discard.include?(tmp_a[0])
        tmp_a2=[:none,0,:asc]
        tmp_a2[2] = :desc if tmp_a.size > 1 && tmp_a[1].upcase == 'DESC'
        cl=tmp_a[0].split('.')
        case cl[0]
          when 'users'
            tmp_a2[0]=:assigned_to
          when 'authors'
            tmp_a2[0]=:author
          when 'versions'
            tmp_a2[0]=:version
          when 'projects'
            tmp_a2[0]=:project
          when 'trackers'
            tmp_a2[0]=:tracker
          when 'enumerations'
            tmp_a2[0]=:priority
          when 'issue_statuses'
            tmp_a2[0]=:status
          when 'issue_categories'
            tmp_a2[0]=:category
          when 'cfield'
            tmp_a2[0]=:cfield
            tmp_a2[1]=cl[1].to_i
          when 'issues'
            if cl[1] != 'lft'
              i=Issue.new
              if i.respond_to?(cl[1].to_sym)
                tmp_a2[0]=:issue
                tmp_a2[1]=cl[1].to_sym
              end
            else
              parent_involved=true
              tmp_a2[0]=:issue_parent
            end
        end
        options_array << tmp_a2 unless tmp_a2[0] == :none
      end
    end
    return {:options => options_array, :parent_involved => (parent_involved ? true : false)}
  end

  # query_options: :conditions, :find_conditions, :joins, :offset, :limit, :include
  # sort_options: array of sort keys with three members array [base_key, key_option,:desc | :asc] values
  # sort keys are:
  #   :assigned_to, :author, :version, :project, :tracker, :priority, :status
  #   :category, :cfield ([field_id]), :issue_parent, :issue [ATTR_NAME] (ie :start_date)
  # nil_values_first = true if nil values have priority over non-nil values
  def self.get_issues_sorted_list_from_db(sort_options,query_options={},
      issue_ids_only=false,nil_values_first=false,logger=nil)
    issues = Issue.visible.scoped(:conditions => query_options[:conditions]).find(:all,
                     :include => ([:status, :project] + (query_options[:include] || [])).uniq,
                     :conditions => query_options[:find_conditions],
                     :joins => query_options[:joins])

    sorted_issues=get_issues_sorted_list(sort_options,issues,false,nil_values_first,logger)

    offset=(query_options[:offset] || 0).to_i
    limit=(query_options[:limit] || 1000000).to_i

    return [] if offset >= sorted_issues.size

    limit=sorted_issues.size - offset if (offset+limit) > sorted_issues.size

    if issue_ids_only
      limit.times do |i|
        issues << sorted_issues[offset+i].id
      end
    else
      issues=sorted_issues[offset...(offset+limit)]
    end
    issues
  end

  def self.get_issues_sorted_list(sort_options,issues,in_place=false,nil_values_first=false,logger=nil)
    sort_options=normalize_sort_options(sort_options)

    logger.info do
      s=''
      s << "QUERY order: \n"
      sort_options.each do |o|
        s << "  #{o[0].to_s} #{o[1].to_s} #{o[2].to_s} #{o[3].to_s}\n"
      end
      s
    end if logger

    sort_values=populate_issues_sort_values(sort_options,issues,logger)

    if in_place
      issues.sort! do |issue_a, issue_b|
        compare_issues(sort_options,sort_values,issue_a,issue_b,nil_values_first,nil)
      end
    else
      sorted_issues=issues.sort do |issue_a, issue_b|
        compare_issues(sort_options,sort_values,issue_a,issue_b,nil_values_first,nil)
      end
      return sorted_issues
    end
  end

  COMMON_SORT_FIELD = 0
  VERSION_SORT_FIELD = 1
  PARENT_SORT_FIELD = 2
  CUSTOM_SORT_FIELD = 3
  ISSUE_SORT_FIELD = 4

  SORT_ASCENDING = 0
  SORT_DESCENDING = 1

  # they will become [field_type,hash_symbol,extra data,sort(0-asc,1-desc)]
  def self.normalize_sort_options(sort_options)
    norm_options=[]
    sort_options.each do |option|
      opt_array=[COMMON_SORT_FIELD,0,0,SORT_ASCENDING]
      case option[0]
        when :cfield
          opt_array[0]=CUSTOM_SORT_FIELD
          opt_array[1]="#{option[0].to_s}_#{option[1].to_s}".to_sym
          opt_array[2]=option[1].to_i
        when :version
          opt_array[0]=VERSION_SORT_FIELD
          opt_array[1]=option[0]
        when :issue_parent
          opt_array[0]=PARENT_SORT_FIELD
          opt_array[1]=option[0]
        when :issue
          opt_array[0]=ISSUE_SORT_FIELD
          opt_array[1]="#{option[0].to_s}_#{option[1].to_s}".to_sym
          opt_array[2]=option[1].to_sym
        else
          opt_array[1]=option[0]
      end
      opt_array[3] = SORT_DESCENDING if option[2] == :desc && opt_array[0] != PARENT_SORT_FIELD
      norm_options << opt_array
    end
    norm_options
  end

  def self.populate_issues_sort_values(sort_options,issues,logger=nil)
    sort_values={}
    issues.each do |issue|
      sort_values[issue.id]=populate_issue_sort_values(sort_options,issue,logger)
    end
    sort_values
  end

  def self.populate_issue_sort_values(sort_options,issue,logger=nil)
    issue_values={}
    sort_options.each do |option|
      case option[1]
        when :assigned_to
          issue_values[option[1]]=issue.assigned_to ? issue.assigned_to.to_s : nil
        when :author
          issue_values[option[1]]=issue.author ? issue.author.to_s : nil
        when :version
          #taken from version.rb for speeding process up, array of effective date and name string
          issue_values[option[1]]=(issue.fixed_version ? [issue.fixed_version.effective_date,"#{issue.fixed_version.project.name} - #{issue.fixed_version.name}"] : nil)
        when :project
          #taken from project.rb for speeding process up, name in downcase
          issue_values[option[1]]=(issue.project ? issue.project.name.downcase : nil)
        when :tracker
          #taken from tracker.rb for speeding process up, name in downcase
          issue_values[option[1]]=(issue.tracker ? issue.tracker.position : nil)
        when :priority
          issue_values[option[1]]=(issue.priority ? issue.priority.position : nil)
        when :status
          issue_values[option[1]]=(issue.status ? issue.status.position : nil)
        when :category
          issue_values[option[1]]=(issue.category ? issue.category.name : nil)
        when :issue_parent
          issue_values[option[1]]=[issue.parent_id,issue.self_and_ancestors]
        else
          case option[0]
            when CUSTOM_SORT_FIELD
              issue_values[option[1]]=get_cf_value_by_id(issue,option[2])
            when ISSUE_SORT_FIELD
              issue_values[option[1]]=issue.respond_to?(option[2]) ? issue.send(option[2]) : nil
              logger.info("#{option[1].to_s}:#{issue_values[option[1]].to_s}(#{issue_values[option[1]].class.to_s})") if logger
          end
      end
    end
    issue_values
  end


  def self.compare_issues(order_options_converted,sort_values,issue_a,issue_b,nil_values_first=false,issues=nil)
    order_options_converted.each do |option|
      r=compare_issues_by_single_option(option,order_options_converted,sort_values,issue_a,issue_b,nil_values_first,issues)
      return r if r!=0
    end
    return issue_a.id <=> issue_b.id
  end

  def self.compare_issues_by_single_option(option,all_options,sort_values,issue_a,issue_b,nil_values_first,issues)

    issue=(option[3] == SORT_ASCENDING ? [issue_a,issue_b] : [issue_b,issue_a])

    sort_values[issue[0].id]=populate_issue_sort_values(all_options,issue[0]) unless sort_values[issue[0].id]
    sort_values[issue[1].id]=populate_issue_sort_values(all_options,issue[1]) unless sort_values[issue[1].id]

    values=[sort_values[issue[0].id][option[1]],sort_values[issue[1].id][option[1]]]

    unless option[0] == PARENT_SORT_FIELD
      return 0 if values[0] == nil && values[1] == nil
      if nil_values_first
        return -1 if values[0]==nil
        return 1 if values[1]==nil
      else
        return 1 if values[0]==nil
        return -1 if values[1]==nil
      end
      return values[0] <=> values[1] unless option[0] == VERSION_SORT_FIELD

      # taken from version.rb [0]-effective date, [1] - version comparision string
      if values[0][0]
        if values[1][0]
          return values[0][1] <=> values[1][1] if values[0][0] == values[1][0]
          return values[0][0] <=> values[1][0]
        end
        return -1
      end
      return 1 if values[1][0]
      return values[0][1] <=> values[1][1]
    end

    # parent issues compare
    #parent_id
    return 0 if values[0][0] == values[1][0]

    # always ascending, ancestors and self
    anc_a=values[0][1]
    anc_b=values[1][1]

    return 1 if anc_a.include?(issue[1])
    return -1 if anc_b.include?(issue[0])

    i=0
    while i < anc_a.size && i < anc_b.size && anc_a[i].id == anc_b[i].id
      i=i+1
    end

    return 0 if i >= anc_a.size || i >= anc_b.size

    compare_issues(all_options,sort_values,anc_a[i],anc_b[i],nil_values_first,issues)
  end

  def self.get_cf_value_by_id(issue,cf_id)
    ccf=issue.custom_values.detect do |c|
      true if c.custom_field_id == cf_id
    end
    return ccf != nil ? ccf.custom_field.cast_value(ccf.value) : nil
  end
end
