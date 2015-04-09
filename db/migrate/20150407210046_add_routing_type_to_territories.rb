class AddRoutingTypeToTerritories < ActiveRecord::Migration
  def change
  	add_column :territories, :routing_type, :string
  	add_column :geos, :starting_letter, :string
  end
end
