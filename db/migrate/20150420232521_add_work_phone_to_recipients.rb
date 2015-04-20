class AddWorkPhoneToRecipients < ActiveRecord::Migration
  def change
  	add_column :recipients, :work_phone, :string
  end
end
