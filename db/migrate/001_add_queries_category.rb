  class AddQueriesCategory < ActiveRecord::Migration
    def self.up
      add_column :queries, :category, :string rescue nil
    end

    def self.down
      remove_column :queries, :category
    end
  end
