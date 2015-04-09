class CreateRecipients < ActiveRecord::Migration
  def change
  	create_table :submissions do |t|
			t.text :all_params
			t.string :busPhone
			t.string :caTerritories
			t.string :company
			t.string :country
			t.string :description1
			t.string :emailAddress
			t.string :firstName
			t.string :jobRole
			t.string :lastName
			t.string :postal1
			t.string :ukBoroughs
			t.string :usStates
			t.string :recipient_id
			t.string :status
			t.timestamps null: false
  	end
  	add_index :submissions, :recipient_id

  	create_table :recipients do |t|
			t.string :name
			t.string :email
			t.string :phone
			t.string :hours
			t.timestamps null: false
  	end

  	create_table :geos do |t|
  		t.string :country
  		t.string :sub_country
  		t.string :zip_code
  		t.string :area
  		t.integer :territory_id
			t.timestamps null: false
  	end
  	add_index :geos, :territory_id
  	
  	create_table :territories do |t|
  		t.string :name
  		t.integer :recipient_id
			t.timestamps null: false
  	end
  	add_index :territories, :recipient_id
  end
end
