class AddQueriesParentSortOption < ActiveRecord::Migration
  def self.up
    begin
      add_column :queries, :sort_by_parent_first, :boolean, :default => false

      Query.find(:all).each do |q|
        q.sort_by_parent_first=true
        q.save!
      end
    rescue
      nil
    end
  end

  def self.down
    remove_column :queries, :sort_by_parent_first
  end
end
