# frozen_string_literal: true

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "mcp_items#index"

  post "mcp_items", to: "mcp_items#create", as: :mcp_items
  patch "mcp_items/:id/complete", to: "mcp_items#complete", as: :complete_mcp_item
  patch "mcp_items/:id/toggle", to: "mcp_items#toggle", as: :toggle_mcp_item
end
