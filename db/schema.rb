# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20150407210046) do

  create_table "geos", force: :cascade do |t|
    t.string   "country"
    t.string   "sub_country"
    t.string   "zip_code"
    t.string   "area"
    t.integer  "territory_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "starting_letter"
  end

  add_index "geos", ["territory_id"], name: "index_geos_on_territory_id"

  create_table "recipients", force: :cascade do |t|
    t.string   "name"
    t.string   "email"
    t.string   "phone"
    t.string   "hours"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "submissions", force: :cascade do |t|
    t.text     "all_params"
    t.string   "busPhone"
    t.string   "caTerritories"
    t.string   "company"
    t.string   "country"
    t.string   "description1"
    t.string   "emailAddress"
    t.string   "firstName"
    t.string   "jobRole"
    t.string   "lastName"
    t.string   "postal1"
    t.string   "ukBoroughs"
    t.string   "usStates"
    t.string   "recipient_id"
    t.string   "status"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "submissions", ["recipient_id"], name: "index_submissions_on_recipient_id"

  create_table "territories", force: :cascade do |t|
    t.string   "name"
    t.integer  "recipient_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "routing_type"
  end

  add_index "territories", ["recipient_id"], name: "index_territories_on_recipient_id"

  create_table "users", force: :cascade do |t|
    t.string   "email"
    t.string   "password"
    t.string   "remember_token"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "users", ["email"], name: "index_users_on_email", unique: true
  add_index "users", ["remember_token"], name: "index_users_on_remember_token"

end
