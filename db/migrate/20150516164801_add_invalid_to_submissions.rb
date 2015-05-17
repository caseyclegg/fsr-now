class AddInvalidToSubmissions < ActiveRecord::Migration
  def change
  	add_column :submissions, :invalid_entry, :boolean
  end
end
