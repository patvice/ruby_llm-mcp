# frozen_string_literal: true

# RubyLLM MCP OAuth routes
resources :mcp_connections, only: [:index] do
  collection do
    get :connect
    get :callback
  end
  member do
    delete :disconnect
    get :refresh
  end
end
