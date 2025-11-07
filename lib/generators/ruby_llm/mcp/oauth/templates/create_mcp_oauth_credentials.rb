# frozen_string_literal: true

class CreateMcpOauthCredentials < ActiveRecord::Migration[7.0]
  def change
    create_table :mcp_oauth_credentials do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :server_url, null: false
      t.text :token_data, null: false
      t.text :client_info_data
      t.datetime :token_expires_at
      t.datetime :last_refreshed_at

      t.timestamps

      t.index %i[user_id server_url], unique: true, name: "index_mcp_oauth_on_user_and_server"
    end
  end
end
