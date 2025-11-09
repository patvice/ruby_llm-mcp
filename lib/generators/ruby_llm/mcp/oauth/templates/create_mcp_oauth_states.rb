# frozen_string_literal: true

class CreateMcpOauthStates < ActiveRecord::Migration[7.0]
  def change
    create_table :mcp_oauth_states do |t|
      t.references :user, null: false, foreign_key: true
      t.string :server_url, null: false
      t.string :state_param, null: false
      t.text :pkce_data, null: false
      t.datetime :expires_at, null: false

      t.timestamps

      t.index %i[user_id state_param], unique: true, name: "index_mcp_oauth_states_on_user_and_state"
      t.index :expires_at, name: "index_mcp_oauth_states_on_expires_at"
    end
  end
end
