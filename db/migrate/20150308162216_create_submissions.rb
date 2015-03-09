class CreateSubmissions < ActiveRecord::Migration
  def change
  	create_table :submissions do |t|
			t.text :all_params
			t.string :company
			t.string :country
			t.string :description1
			t.string :emailAddress
			t.string :firstName
			t.string :jobRole
			t.string :lastName
			t.string :usStates
			t.string :caTerritories
			t.string :bdr
			t.timestamps
  	end
  end
end
